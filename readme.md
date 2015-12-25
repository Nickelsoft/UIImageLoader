# UIImageLoader

UIImageLoader is a helper to load images from the web. It caches images on disk, and optionally in memory.

It makes it super simple to write handler code for cached images, set a placeholder image or show a loader when a network request is being made, and handle any errors on request completion.

It supports server cache control to re-download images when expired. Cache control logic is implemented manually instead of using an NSURLCache for performance reasons.

You can also completely ignore server cache control and manually clean-up images yourself.

It's compatible with iOS and Mac. And very small at roughly 600+ lines of code in a single header / implementation file.

Everything is asynchronous and uses modern objective-c with libdispatch and NSURLSession.

## Server Cache Control

It supports responses with Cache-Control max age, ETag, and Last-Modified headers.

It sends requests with If-None-Match, and If-Modified-Since.

If the server doesn't respond with a Cache-Control header, you can optionally set a default cache control max age in order to cache the image for a specified time.

If a response is 304 it uses the cached image available on disk.

## Installation

* Download a zip of this repo
* Add UIImageLoader.h and UIImageLoader.m to your Xcode project

## Dribbble Samples

There's a very simple sample application for iOS/Mac that shows loading images into a collection view.

The app loads 1000 images from Dribbble.

The app demonstrates how to setup a cell to gracefully handle:

* Downloading images
* Using spinners for loading activity
* Cancelling an image download when a cell is reused
* Or letting the image download complete so it's cached

![sample screenshots](http://www.gngrwzrd.com/downloads/dribbble-samples-mac-ios-1.png)

## UIImageLoader Object

There's a default configured loader which you're free to configure how you like.

````
//this is the default configuration:

- (id) initWithCacheDirectory:(NSURL *) url; {
	self = [super init];
	self.cacheImagesInMemory = FALSE;
	self.trustAnySSLCertificate = FALSE;
	self.useServerCachePolicy = TRUE;
	self.logCacheMisses = TRUE;
	self.logResponseWarnings = TRUE;
	self.defaultCacheControlMaxAge = 0;
	self.memoryCache = [[UIImageMemoryCache alloc] init];
	self.cacheDirectory = url;
	self.acceptedContentTypes = @[@"image/png",@"image/jpg",@"image/jpeg",@"image/bmp",@"image/gif",@"image/tiff"];
	return self;
}

````

Or you can setup your own and configure it:

````
//create loader
UIImageLoader * loader = [[UIImageLoader alloc] initWithCacheDirectory:myCustomDiskURL];
//set loader properties here.
````

### Loading an Image

It's easy to load an image:

````
NSURL * imageURL = myURL;	

[[UIImageLoader defaultLoader] loadImageWithURL:imageURL \

hasCache:^(UIImageLoaderImage * image, UIImageLoadSource loadedFromSource) {
	
	//there was a cached image available. use that.
	self.imageView.image = image;
	
} sendRequest:^(BOOL didHaveCachedImage) {
	
	//a request is being made for the image.
	
	if(!didHaveCachedImage) {
		
		//there was not a cached image available, set a placeholder or do nothing.
		self.loader.hidden = FALSE;
	    [self.loader startAnimating];
	    self.imageView.image = [UIImage imageNamed:@"placeholder"];
	}
	
} requestCompleted:^(NSError *error, UIImageLoaderImage * image, UIImageLoadSource loadedFromSource) {
	
	//network request finished.
	
	[self.loader stopAnimating];
	self.loader.hidden = TRUE;
	
	if(loadedFromSource == UIImageLoadSourceNetworkToDisk) {
		//the image was downloaded and saved to disk.
		//since it was downloaded it has been updated since
		//last cached version, or is brand new
	
		self.imageView.image = image;
	}
}];
````

### Image Loaded Source

The enum UIImageLoadSource provides you with where the image was loaded from:

````
//image source passed in completion callbacks.
typedef NS_ENUM(NSInteger,UIImageLoadSource) {
	
	//this is passed to callbacks when there's an error, no image is provided.
	UIImageLoadSourceNone,               //no image source as there was an error.
	
	//these will be passed to your hasCache callback
	UIImageLoadSourceDisk,               //image was cached on disk already and loaded from disk
	UIImageLoadSourceMemory,             //image was in memory cache
	
    //these will be passed to your requestCompleted callback
	UIImageLoadSourceNetworkNotModified, //a network request was sent but existing content is still valid
	UIImageLoadSourceNetworkToDisk,      //a network request was sent, image was updated on disk
	
};
````

### Has Cache Callback

When you load an image with UIImageLoader, the first callback you can use is the _hasCache_ callback. It's defined as:

````
typedef void(^UIImageLoader_HasCacheBlock)(UIImageLoaderImage * image, UIImageLoadSource loadedFromSource);
````

If a cached image is available, you will get the image, and the source will be either UIImageLoadSourceDisk or UIImageLoadSourceMemory.

### Send Request Callback

You can use this callback to decide if you should show a placeholder or loader of some kind. If the image loader needs to make a request for the image, you will receive this callback. It's defined as:

````
typedef void(^UIImageLoader_SendingRequestBlock)(BOOL didHaveCachedImage);
````

The _didHaveCachedImage_ parameter tells you if a cached image was available (and that your _hasCache_ callback was called).

### Request Completed Callback

This callback runs when the request has finished. It's defined as:

````
typedef void(^UIImageLoader_RequestCompletedBlock)(NSError * error, UIImageLoaderImage * image, UIImageLoadSource loadedFromSource);
````

If a network error occurs, you'll receive an _error_ object and _UIImageLoadSourceNone_.

If load source is _UIImageLoadSourceNetworkToDisk_, it means a new image was downloaded. Either it was a new download, or existing cache was updated. You should use the new image provided.

If load source is _UIImageLoadSourceNetworkNotModified_, it means the cached image is still valid. You won't receive an image in this case as the image was already passed to your _hasCache_ callback.

### Accepted Image Types

You can customize the accepted content-types types from servers with:

````
loader.acceptedContentTypes = @[@"image/png",@"image/jpg",@"image/jpeg",@"image/bmp",@"image/gif",@"image/tiff"];
````

### Memory Cache

You can enable the memory cache easily:

````
UIImageLoader * loader = [UIImageLoader defaultLoader];
loader.cacheImagesInMemory = TRUE;
````

You can change the memory limit with:

````
UIImageLoader * loader = [UIImageLoader defaultLoader];
[loader setMemoryCacheMaxBytes:50 * (1024 * 1024)]; //50MB
````

You can purge memory with:

````
UIImageLoader * loader = [UIImageLoader defaultLoader];
[loader purgeMemoryCache];
````

_Memory cache is not shared among loaders, each loader will have it's own cache._

### Manual Disk Cache Cleanup

When an image is accessed using UIImageLoader the file's modified date is updated.

These methods use the file modified date to decide which to delete. You can use these methods to ensure frequently used files will not be delete.

````
- (void) clearCachedFilesModifiedOlderThan1Day;
- (void) clearCachedFilesModifiedOlderThan1Week;
- (void) clearCachedFilesModifiedOlderThan:(NSTimeInterval) timeInterval;
````

These methods use the file created date to decide which to delete.

````
- (void) clearCachedFilesCreatedOlderThan1Day;
- (void) clearCachedFilesCreatedOlderThan1Week;
- (void) clearCachedFilesCreatedOlderThan:(NSTimeInterval) timeInterval;
````

You can purge the entire disk cache with:

````
- (void) purgeDiskCache;
````

It's easy to put some cleanup in app delegate. Using one of the methods available you can keep the disk cache clean, while keeping frequently used images.

````
- (BOOL) application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIImageLoader * loader = [UIImageLoader defaultLoader];
    [loader clearCachedFilesModifiedOlderThan1Week];
}
````

### 304 Not Modified Images

For image responses that return a 304, but don't include a Cache-Control header (expiration), the default behavior is to always send requests to check for new content. Even if there's a cached version available, a network request would still be sent.

You can set a default cache time for this scenario in order to stop these requests.

````
myCache.defaultCacheControlMaxAge = 604800; //1 week;
myCache.defaultCacheControlMaxAge = 0;      //(default) always send request to see if there's new content.
````

### NSURLSession

You can customize the NSURLSession that's used to download images like this:

````
myCache.session = myNSURLSession;
````

If you do customize the session. Make sure to use a session that runs on a background thread:

````
NSURLSessionConfiguration * config = [NSURLSessionConfiguration defaultSessionConfiguration];
loader.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[[NSOperationQueue alloc] init]];
````

You are responsible for implementing it's delegate if required. And implementing SSL trust for self signed certificates if required.

### NSURLSessionDataTask

Each load method returns the NSURLSessionDataTask used for network requests. You can either ignore it, or keep it. It's useful for canceling requests if needed.

## Other Useful Features

### SSL

If you need to support self signed certificates you can use (false by default):

````
myLoader.trustAnySSLCertificate = TRUE;
````

### Auth Basic Password Protected Directories/Images

You can set default user/pass that gets sent in every request with:

````
[myLoader setAuthUsername:@"username" password:@"password"];
````

### UIImageLoaderImage For Mac OS X

For compatibility between platforms, there's a typedef that UIImageLoader uses to switch out image types.

````
// UIImageLoaderImage - typedef for ios/mac compatibility
#if TARGET_OS_IPHONE
typedef UIImage UIImageLoaderImage;
#elif TARGET_OS_MAC
typedef NSImage UIImageLoaderImage;
#endif
````

# License

The MIT License (MIT)
Copyright (c) 2016 Aaron Smith

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.