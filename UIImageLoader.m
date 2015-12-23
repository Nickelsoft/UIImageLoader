
#import "UIImageLoader.h"

/**********************/
/* UIImageMemoryCache */
/**********************/

@interface UIImageMemoryCache ()
@property NSCache * cache;
@end

@implementation UIImageMemoryCache

- (id) init {
	self = [super init];
	self.cache = [[NSCache alloc] init];
	self.cache.totalCostLimit = 25 * (1024 * 1024); //25MB
	return self;
}

- (void) cacheImage:(UIImageLoaderImage *) image forURL:(NSURL *) url; {
	if(image) {
		NSUInteger cost = CGImageGetHeight(image.CGImage) * CGImageGetBytesPerRow(image.CGImage);
		[self.cache setObject:image forKey:url.path cost:cost];
	}
}

- (void) removeImageForURL:(NSURL *) url; {
	[self.cache removeObjectForKey:url.path];
}

- (void) purge; {
	[self.cache removeAllObjects];
}

@end

/* UIImageCacheData */
@interface UIImageCacheData : NSObject <NSCoding>
@property NSTimeInterval maxage;
@property NSString * etag;
@property BOOL nocache;
@end

/* UIImageLoader */
typedef void(^UIImageLoadedBlock)(UIImageLoaderImage * image);
typedef void(^NSURLAndDataWriteBlock)(NSURL * url, NSData * data);
typedef void(^UIImageLoaderURLCompletion)(NSError * error, NSURL * diskURL, UIImageLoadSource loadedFromSource);
typedef void(^UIImageLoaderDiskURLCompletion)(NSURL * diskURL);

//errors
NSString * const UIImageLoaderErrorDomain = @"com.gngrwzrd.UIImageDisckCache";
const NSInteger UIImageLoaderErrorResponseCode = 1;
const NSInteger UIImageLoaderErrorContentType = 2;
const NSInteger UIImageLoaderErrorNilURL = 3;

//default loader
static UIImageLoader * _default;

//private loader properties
@interface UIImageLoader ()
@property NSURLSession * activeSession;
@property (readwrite) NSURL * cacheDirectory;
@property NSString * auth;
@end

@implementation UIImageLoader

+ (UIImageLoader *) defaultLoader {
	if(!_default) {
		_default = [[UIImageLoader alloc] init];
	}
	return _default;
}

- (id) init {
	NSURL * appSupport = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
	NSURL * defaultCacheDir = [appSupport URLByAppendingPathComponent:@"UIImageLoader"];
	[[NSFileManager defaultManager] createDirectoryAtURL:defaultCacheDir withIntermediateDirectories:TRUE attributes:nil error:nil];
	self = [self initWithCacheDirectory:defaultCacheDir];
	return self;
}

- (id) initWithCacheDirectory:(NSURL *) url; {
	self = [super init];
	self.cacheImagesInMemory = FALSE;
	self.trustAnySSLCertificate = FALSE;
	self.useServerCachePolicy = TRUE;
	self.logCacheMisses = TRUE;
	self.logResponseWarnings = TRUE;
	self.etagOnlyCacheControl = 0;
	self.memoryCache = [[UIImageMemoryCache alloc] init];
	self.cacheDirectory = url;
	self.acceptedContentTypes = @[@"image/png",@"image/jpg",@"image/jpeg",@"image/bmp",@"image/gif",@"image/tiff"];
	return self;
}

- (void) setAuthUsername:(NSString *) username password:(NSString *) password; {
	if(username == nil || password == nil) {
		self.auth = nil;
		return;
	}
	NSString * authString = [NSString stringWithFormat:@"%@:%@",username,password];
	NSData * authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
	NSString * encoded = [authData base64EncodedStringWithOptions:0];
	self.auth = [NSString stringWithFormat:@"Basic %@",encoded];
}

- (void) setAuthorization:(NSMutableURLRequest *) request {
	if(self.auth) {
		[request setValue:self.auth forHTTPHeaderField:@"Authorization"];
	}
}

- (void) clearCachedFilesOlderThan1Day; {
	[self clearCachedFilesOlderThan:86400];
}

- (void) clearCachedFilesOlderThan1Week; {
	[self clearCachedFilesOlderThan:604800];
}

- (void) clearCachedFilesOlderThan:(NSTimeInterval) timeInterval; {
	dispatch_queue_t background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
	dispatch_async(background, ^{
		NSArray * files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.cacheDirectory.path error:nil];
		for(NSString * file in files) {
			NSURL * path = [self.cacheDirectory URLByAppendingPathComponent:file];
			NSDictionary * attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path.path error:nil];
			NSDate * modified = attributes[NSFileModificationDate];
			NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:modified];
			if(diff > timeInterval) {
				NSLog(@"deleting cached file: %@",path.path);
				[[NSFileManager defaultManager] removeItemAtPath:path.path error:nil];
			}
		}
	});
}

- (void) setSession:(NSURLSession *) session {
	self.activeSession = session;
	if(session.delegate && self.trustAnySSLCertificate) {
		if(![session.delegate respondsToSelector:@selector(URLSession:didReceiveChallenge:completionHandler:)]) {
			NSLog(@"[UIImageLoader] WARNING: You set a custom NSURLSession and require trustAnySSLCertificate but your "
				  @"session delegate doesn't respond to URLSession:didReceiveChallenge:completionHandler:");
		}
	}
}

- (NSURLSession *) session {
	if(self.activeSession) {
		return self.activeSession;
	}
	
	NSURLSessionConfiguration * config = [NSURLSessionConfiguration defaultSessionConfiguration];
	self.activeSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[[NSOperationQueue alloc] init]];
	
	return self.activeSession;
}

- (void) URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
	if(self.trustAnySSLCertificate) {
		completionHandler(NSURLSessionAuthChallengeUseCredential,[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
	} else {
		completionHandler(NSURLSessionAuthChallengePerformDefaultHandling,nil);
	}
}

- (NSURL *) localFileURLForURL:(NSURL *) url {
	if(!url) {
		return NULL;
	}
	NSString * path = [url.absoluteString stringByRemovingPercentEncoding];
	NSString * path2 = [path stringByReplacingOccurrencesOfString:@"http://" withString:@""];
	path2 = [path2 stringByReplacingOccurrencesOfString:@"https://" withString:@""];
	path2 = [path2 stringByReplacingOccurrencesOfString:@":" withString:@"-"];
	path2 = [path2 stringByReplacingOccurrencesOfString:@"?" withString:@"-"];
	path2 = [path2 stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
	path2 = [path2 stringByReplacingOccurrencesOfString:@" " withString:@"_"];
	return [self.cacheDirectory URLByAppendingPathComponent:path2];
}

- (NSURL *) localCacheControlFileURLForURL:(NSURL *) url {
	if(!url) {
		return NULL;
	}
	NSURL * localImageFile = [self localFileURLForURL:url];
	NSString * path = [localImageFile.path stringByAppendingString:@".cc"];
	return [NSURL fileURLWithPath:path];
}

- (BOOL) acceptedContentType:(NSString *) contentType {
	return [self.acceptedContentTypes containsObject:contentType];
}

- (NSDate *) createdDateForFileURL:(NSURL *) url {
	NSDictionary * attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
	if(!attributes) {
		return nil;
	}
	return attributes[NSFileCreationDate];
}

- (void) writeData:(NSData *) data toFile:(NSURL *) cachedURL writeCompletion:(NSURLAndDataWriteBlock) writeCompletion {
	dispatch_queue_t background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
	dispatch_async(background, ^{
		[data writeToFile:cachedURL.path atomically:TRUE];
		if(writeCompletion) {
			writeCompletion(cachedURL,data);
		}
	});
}

- (void) writeCacheControlData:(UIImageCacheData *) cache toFile:(NSURL *) cachedURL {
	dispatch_queue_t background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
	dispatch_async(background, ^{
		NSData * data = [NSKeyedArchiver archivedDataWithRootObject:cache];
		[data writeToFile:cachedURL.path atomically:TRUE];
		NSDictionary * attributes = @{NSFileModificationDate:[NSDate date]};
		[[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:cachedURL.path error:nil];
	});
}

- (void) loadImageInBackground:(NSURL *) diskURL completion:(UIImageLoadedBlock) completion {
	dispatch_queue_t background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
	dispatch_async(background, ^{
		NSDate * modified = [NSDate date];
		NSDictionary * attributes = @{NSFileModificationDate:modified};
		[[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:diskURL.path error:nil];
		NSURL * cachedInfoFile = [diskURL URLByAppendingPathExtension:@"cc"];
		[[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:cachedInfoFile.path error:nil];
		UIImageLoaderImage * image = [[UIImageLoaderImage alloc] initWithContentsOfFile:diskURL.path];
		if(completion) {
			completion(image);
		}
	});
}

- (void) setCacheControlForCacheInfo:(UIImageCacheData *) cacheInfo fromCacheControlString:(NSString *) cacheControl {
	if([cacheControl isEqualToString:@"no-cache"]) {
		cacheInfo.nocache = TRUE;
		return;
	}
	
	NSScanner * scanner = [[NSScanner alloc] initWithString:cacheControl];
	NSString * prelim = nil;
	[scanner scanUpToString:@"=" intoString:&prelim];
	[scanner scanString:@"=" intoString:nil];
	
	double maxage = -1;
	[scanner scanDouble:&maxage];
	if(maxage > -1) {
		cacheInfo.maxage = (NSTimeInterval)maxage;
	}
}

- (NSURLSessionDataTask *) cacheImageWithRequestUsingCacheControl:(NSURLRequest *) request
	hasCache:(UIImageLoaderDiskURLCompletion) hasCache
	sendRequest:(UIImageLoader_SendingRequestBlock) sendRequest
	requestCompleted:(UIImageLoaderURLCompletion) requestCompleted {
	
	if(!request.URL) {
		NSLog(@"[UIImageLoader] ERROR: request.URL was NULL");
		requestCompleted([NSError errorWithDomain:UIImageLoaderErrorDomain code:UIImageLoaderErrorNilURL userInfo:@{NSLocalizedDescriptionKey:@"request.URL is nil"}],nil,UIImageLoadSourceNone);
	}
	
	//make mutable request
	NSMutableURLRequest * mutableRequest = [request mutableCopy];
	[self setAuthorization:mutableRequest];
	
	//get cache file urls
	NSURL * cacheInfoFile = [self localCacheControlFileURLForURL:request.URL];
	NSURL * cachedImageURL = [self localFileURLForURL:request.URL];
	
	//setup blank cache object
	UIImageCacheData * cached = nil;
	
	//load cached info file if it exists.
	if([[NSFileManager defaultManager] fileExistsAtPath:cacheInfoFile.path]) {
		cached = [NSKeyedUnarchiver unarchiveObjectWithFile:cacheInfoFile.path];
	} else {
		cached = [[UIImageCacheData alloc] init];
	}
	
	//check max age
	NSDate * now = [NSDate date];
	NSDate * createdDate = [self createdDateForFileURL:cachedImageURL];
	NSTimeInterval diff = [now timeIntervalSinceDate:createdDate];
	BOOL cacheValid = FALSE;
	
	//check cache expiration
	if(!cached.nocache && cached.maxage > 0 && diff < cached.maxage) {
		cacheValid = TRUE;
	}
	
	BOOL didSendCacheCompletion = FALSE;
	
	//file exists.
	if([[NSFileManager defaultManager] fileExistsAtPath:cachedImageURL.path]) {
		if(cacheValid) {
			hasCache(cachedImageURL);
			return nil;
		} else {
			didSendCacheCompletion = TRUE;
			//call hasCache completion and continue load below
			hasCache(cachedImageURL);
		}
	} else {
		if(self.logCacheMisses) {
			NSLog(@"[UIImageLoader] cache miss for url: %@",request.URL);
		}
	}
	
	//ignore built in cache from networking code. handled here instead.
	mutableRequest.cachePolicy = NSURLRequestReloadIgnoringCacheData;
	
	//check if there's an etag from the server available.
	if(cached.etag) {
		[mutableRequest setValue:cached.etag forHTTPHeaderField:@"If-None-Match"];
		
		if(self.etagOnlyCacheControl > 0) {
			cached.maxage = self.etagOnlyCacheControl;
		}
		
		if(cached.maxage == 0  && self.etagOnlyCacheControl < 1) {
			if(self.logResponseWarnings) {
				NSLog(@"[UIImageLoader] WARNING: Cached Image response ETag is set but no Cache-Control is available. "
					  @"Image requests will always be sent, the response may or may not be 304. "
					  @"Add Cache-Control policies to the server to correctly have content expire locally. "
					  @"URL: %@",mutableRequest.URL);
			}
		}
	}
	
	sendRequest(didSendCacheCompletion);
	
	__weak UIImageLoader * weakself = self;
	
	NSURLSessionDataTask * task = [[self session] dataTaskWithRequest:mutableRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if(error) {
			if(error.code == -999 && [error.domain isEqualToString:@"NSURLErrorDomain"]) {
				requestCompleted(error,nil,UIImageLoadSourceNetworkCancelled);
			} else {
				requestCompleted(error,nil,UIImageLoadSourceNone);
			}
			return;
		}
		
		NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
		NSDictionary * headers = [httpResponse allHeaderFields];
		
		//304 Not Modified. Use Cache.
		if(httpResponse.statusCode == 304) {
			
			if(headers[@"Cache-Control"]) {
				
				NSString * control = headers[@"Cache-Control"];
				[self setCacheControlForCacheInfo:cached fromCacheControlString:control];
				[self writeCacheControlData:cached toFile:cacheInfoFile];
			
			} else {
				
				if(headers[@"ETag"] && self.etagOnlyCacheControl > 0) {
					cached.maxage = self.etagOnlyCacheControl;
					[self writeCacheControlData:cached toFile:cacheInfoFile];
				}
				
			}
			
			requestCompleted(nil,cachedImageURL,UIImageLoadSourceNetworkNotModified);
			return;
		}
		
		//status not OK, error.
		if(httpResponse.statusCode != 200) {
			NSString * message = [NSString stringWithFormat:@"Invalid image cache response %li",(long)httpResponse.statusCode];
			requestCompleted([NSError errorWithDomain:UIImageLoaderErrorDomain code:UIImageLoaderErrorResponseCode userInfo:@{NSLocalizedDescriptionKey:message}],nil,UIImageLoadSourceNone);
			return;
		}
		
		//check that content type is an image.
		NSString * contentType = headers[@"Content-Type"];
		if(![weakself acceptedContentType:contentType]) {
			requestCompleted([NSError errorWithDomain:UIImageLoaderErrorDomain code:UIImageLoaderErrorContentType userInfo:@{NSLocalizedDescriptionKey:@"Response was not an image"}],nil,UIImageLoadSourceNone);
			return;
		}
		
		//check response for etag and cache control
		if(!headers[@"ETag"] && !headers[@"Cache-Control"]) {
			if(self.logResponseWarnings) {
				NSLog(@"[UIImageLoader] WARNING: You are loading images using the server cache control but the server returned neither ETag or Cache-Control. "
					  @"Images will continue to load every time the image is needed. "
					  @"URL: %@",mutableRequest.URL);
			}
		}
		
		if(headers[@"ETag"]) {
			cached.etag = headers[@"ETag"];
			
			if(self.etagOnlyCacheControl > 0) {
				cached.maxage = self.etagOnlyCacheControl;
			}
			
			if(!headers[@"Cache-Control"] && self.etagOnlyCacheControl < 1) {
				if(self.logResponseWarnings ) {
					NSLog(@"[UIImageLoader] WARNING: Image response header ETag is set but no Cache-Control is available. "
						  @"You can set a custom cache control for this scenario with the etagOnlyCacheControl property. "
						  @"Image requests will always be sent, the response may or may not be 304. "
						  @"Optionally add Cache-Control policies to the server to correctly have content expire locally. "
						  @"URL: %@",mutableRequest.URL);
				}
			}
		}
		
		if(headers[@"Cache-Control"]) {
			NSString * control = headers[@"Cache-Control"];
			[self setCacheControlForCacheInfo:cached fromCacheControlString:control];
		}
		
		//save cached info file
		[weakself writeCacheControlData:cached toFile:cacheInfoFile];
		
		//save image to disk
		[weakself writeData:data toFile:cachedImageURL writeCompletion:^(NSURL *url, NSData *data) {
			requestCompleted(nil,cachedImageURL,UIImageLoadSourceNetworkToDisk);
		}];
	}];
	
	[task resume];
	
	return task;
}

- (NSURLSessionDataTask *) cacheImageWithRequest:(NSURLRequest *) request
	hasCache:(UIImageLoaderDiskURLCompletion) hasCache
	sendRequest:(UIImageLoader_SendingRequestBlock) sendRequest
	requestComplete:(UIImageLoaderURLCompletion) requestComplete {
	
	//if use server cache policies, use other method.
	if(self.useServerCachePolicy) {
		return [self cacheImageWithRequestUsingCacheControl:request hasCache:hasCache sendRequest:sendRequest requestCompleted:requestComplete];
	}
	
	if(!request.URL) {
		NSLog(@"[UIImageLoader] ERROR: request.URL was NULL");
		requestComplete([NSError errorWithDomain:UIImageLoaderErrorDomain code:UIImageLoaderErrorNilURL userInfo:@{NSLocalizedDescriptionKey:@"request.URL is nil"}],nil,UIImageLoadSourceNone);
	}
	
	//make mutable request
	NSMutableURLRequest * mutableRequest = [request mutableCopy];
	[self setAuthorization:mutableRequest];
	
	NSURL * cachedURL = [self localFileURLForURL:mutableRequest.URL];
	if([[NSFileManager defaultManager] fileExistsAtPath:cachedURL.path]) {
		hasCache(cachedURL);
		return nil;
	}
	
	if(self.logCacheMisses) {
		NSLog(@"[UIImageLoader] cache miss for url: %@",mutableRequest.URL);
	}
	
	sendRequest(FALSE);
	
	__weak UIImageLoader * weakSelf = self;
	
	NSURLSessionDataTask * task = [[self session] dataTaskWithRequest:mutableRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if(error) {
			if(error.code == -999 && [error.domain isEqualToString:@"NSURLErrorDomain"]) {
				requestComplete(error,nil,UIImageLoadSourceNetworkCancelled);
			} else {
				requestComplete(error,nil,UIImageLoadSourceNone);
			}
			return;
		}
		
		NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
		if(httpResponse.statusCode != 200) {
			NSString * message = [NSString stringWithFormat:@"Invalid image cache response %li",(long)httpResponse.statusCode];
			requestComplete([NSError errorWithDomain:UIImageLoaderErrorDomain code:UIImageLoaderErrorResponseCode userInfo:@{NSLocalizedDescriptionKey:message}],nil,UIImageLoadSourceNone);
			return;
		}
		
		NSString * contentType = [[httpResponse allHeaderFields] objectForKey:@"Content-Type"];
		if(![weakSelf acceptedContentType:contentType]) {
			requestComplete([NSError errorWithDomain:UIImageLoaderErrorDomain code:UIImageLoaderErrorContentType userInfo:@{NSLocalizedDescriptionKey:@"Response was not an image"}],nil,UIImageLoadSourceNone);
			return;
		}
		
		if(data) {
			[weakSelf writeData:data toFile:cachedURL writeCompletion:^(NSURL *url, NSData *data) {
				requestComplete(nil,cachedURL,UIImageLoadSourceNetworkToDisk);
			}];
		}
	}];
	
	[task resume];
	
	return task;
}

- (NSURLSessionDataTask *) loadImageWithRequest:(NSURLRequest *) request
									   hasCache:(UIImageLoader_HasCacheBlock) hasCache
									sendRequest:(UIImageLoader_SendingRequestBlock) sendRequest
							   requestCompleted:(UIImageLoader_RequestCompletedBlock) requestCompleted; {
	
	//check memory cache
	UIImageLoaderImage * image = [self.memoryCache.cache objectForKey:request.URL.path];
	if(image) {
		dispatch_async(dispatch_get_main_queue(), ^{
			hasCache(image,UIImageLoadSourceMemory);
		});
		return nil;
	}
	
	return [self cacheImageWithRequest:request hasCache:^(NSURL *diskURL) {
		
		[self loadImageInBackground:diskURL completion:^(UIImageLoaderImage *image) {
			if(self.cacheImagesInMemory) {
				[self.memoryCache cacheImage:image forURL:request.URL];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				hasCache(image,UIImageLoadSourceDisk);
			});
		}];
		
	} sendRequest:^(BOOL didHaveCache) {
		
		dispatch_async(dispatch_get_main_queue(), ^{
			sendRequest(didHaveCache);
		});
		
	} requestComplete:^(NSError *error, NSURL *diskURL, UIImageLoadSource loadedFromSource) {
		
		if(loadedFromSource == UIImageLoadSourceNetworkToDisk) {
			[self loadImageInBackground:diskURL completion:^(UIImageLoaderImage *image) {
				if(self.cacheImagesInMemory) {
					[self.memoryCache cacheImage:image forURL:request.URL];
				}
				dispatch_async(dispatch_get_main_queue(), ^{
					requestCompleted(error,image,loadedFromSource);
				});
			}];
		} else {
			dispatch_async(dispatch_get_main_queue(), ^{
				requestCompleted(error,nil,loadedFromSource);
			});
		}
		
	}];
}

- (NSURLSessionDataTask *) loadImageWithURL:(NSURL *) url
									   hasCache:(UIImageLoader_HasCacheBlock) hasCache
									sendRequest:(UIImageLoader_SendingRequestBlock) sendRequest
							   requestCompleted:(UIImageLoader_RequestCompletedBlock) requestCompleted; {
	NSURLRequest * request = [NSURLRequest requestWithURL:url];
	return [self loadImageWithRequest:request hasCache:hasCache sendRequest:sendRequest requestCompleted:requestCompleted];
}

@end

/********************/
/* UIImageCacheData */
/********************/

@implementation UIImageCacheData

- (id) init {
	self = [super init];
	self.maxage = 0;
	self.etag = nil;
	return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder {
	self = [super init];
	NSKeyedUnarchiver * un = (NSKeyedUnarchiver *)aDecoder;
	self.maxage = [un decodeDoubleForKey:@"maxage"];
	self.etag = [un decodeObjectForKey:@"etag"];
	self.nocache = [un decodeBoolForKey:@"nocache"];
	return self;
}

- (void) encodeWithCoder:(NSCoder *)aCoder {
	NSKeyedArchiver * ar = (NSKeyedArchiver *)aCoder;
	[ar encodeObject:self.etag forKey:@"etag"];
	[ar encodeDouble:self.maxage forKey:@"maxage"];
	[ar encodeBool:self.nocache forKey:@"nocache"];
}

@end
