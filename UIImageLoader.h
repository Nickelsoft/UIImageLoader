
#import <UIKit/UIKit.h>

/************************/
/** UIImageMemoryCache **/
/************************/

@interface UIImageMemoryCache : NSObject

//max cache size in bytes.
@property (nonatomic) NSUInteger maxBytes;

//cache an image with URL as key.
- (void) cacheImage:(UIImage *) image forURL:(NSURL *) url;

//remove an image with url as key.
- (void) removeImageForURL:(NSURL *) url;

//delete all cache data.
- (void) purge;

@end

/********************/
/* UIImageLoader */
/********************/

//image source passed in completion callbacks.
typedef NS_ENUM(NSInteger,UIImageLoadSource) {
	//these will be passed to your hasCache callback
	UIImageLoadSourceDisk,               //image was cached on disk already and loaded from disk
	UIImageLoadSourceMemory,             //image was in memory cache
	
    //these will be passed to your requestCompleted callback
	UIImageLoadSourceNone,               //no source as there was an error
	UIImageLoadSourceNetworkNotModified, //a network request was sent but existing content is still valid
	UIImageLoadSourceNetworkToDisk,      //a network request was sent, image was updated on disk
};

//forward
@class UIImageLoader;

//completion block
typedef void(^UIImageLoader_HasCacheBlock)(UIImage * image, UIImageLoadSource loadedFromSource);
typedef void(^UIImageLoader_SendingRequestBlock)(BOOL didHaveCachedImage);
typedef void(^UIImageLoader_RequestCompletedBlock)(NSError * error, UIImage * image, UIImageLoadSource loadedFromSource);

//error constants
extern NSString * const UIImageLoaderErrorDomain;
extern const NSInteger UIImageLoaderErrorResponseCode;
extern const NSInteger UIImageLoaderErrorContentType;
extern const NSInteger UIImageLoaderErrorNilURL;

//use the +defaultLoader or create a new one to customize properties.
@interface UIImageLoader : NSObject <NSURLSessionDelegate>

//memory cache where images get stored if cacheImagesInMemory is on.
@property UIImageMemoryCache * memoryCache;

//the session object used to download data.
//If you change this then you are responsible for implementing delegate logic for acceptsAnySSLCertificate if needed.
@property (nonatomic) NSURLSession * session;

//default location is in home/Library/Caches/UIImageLoader
@property (readonly) NSURL * cacheDirectory;

//whether to use server cache policy. Default is TRUE
@property BOOL useServerCachePolicy;

//if useServerCachePolicy=true and response has only ETag header, cache the image for this amount of time. 0 = no cache.
@property NSTimeInterval etagOnlyCacheControl;

//whether to cache loaded images (from disk) into memory.
@property BOOL cacheImagesInMemory;

//Whether to trust any ssl certificate. Default is FALSE
@property BOOL trustAnySSLCertificate;

//Whether to NSLog image urls when there's a cache miss.
@property BOOL logCacheMisses;

//whether to log warnings about response headers.
@property BOOL logResponseWarnings;

//get the default configured loader.
+ (UIImageLoader *) defaultLoader;

//set the Authorization username/password. If set this gets added to every request. Use nil/nil to clear.
- (void) setAuthUsername:(NSString *) username password:(NSString *) password;

//these ignore cache policies and delete files where the modified date is older than specified amount of time.
- (void) clearCachedFilesOlderThan1Day;
- (void) clearCachedFilesOlderThan1Week;
- (void) clearCachedFilesOlderThan:(NSTimeInterval) timeInterval;

//load an image with URL.
- (NSURLSessionDataTask *) loadImageWithURL:(NSURL *) url
								   hasCache:(UIImageLoader_HasCacheBlock) hasCache
								sendRequest:(UIImageLoader_SendingRequestBlock) sendRequest
						   requestCompleted:(UIImageLoader_RequestCompletedBlock) requestCompleted;

//load an image with custom request.
//auth headers will be added to your request if needed.
- (NSURLSessionDataTask *) loadImageWithRequest:(NSURLRequest *) request
									   hasCache:(UIImageLoader_HasCacheBlock) hasCache
									sendRequest:(UIImageLoader_SendingRequestBlock) sendRequest
							   requestCompleted:(UIImageLoader_RequestCompletedBlock) requestCompleted;

@end
