//
//  AFNetworkVirtualFileSystem.h
//  FTP Server
//
//  Created by Keith Duncan on 20/11/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const AFNetworkVirtualFileSystemErrorDomain;

typedef NS_ENUM(NSInteger, AFNetworkVirtualFileSystemErrorCode) {
	AFNetworkVirtualFileSystemErrorCodeUnknown = 0,
	
	AFNetworkVirtualFileSystemErrorCodeNoEntry = -1,
	
	AFNetworkVirtualFileSystemErrorCodeNotContainer = -2,
	AFNetworkVirtualFileSystemErrorCodeNotObject = -3,
};

/*!
	\brief
	An asynchronous storage system.
	
	This file system deals in Containers and Objects (akin to Directories and Files in the UNIX file system model).
	
	It can be mapped to a directory structure in the physical file system, or kept completely virtual.
	
	There is no metadata associated with file system entries.
 */
@protocol AFNetworkVirtualFileSystem <NSObject>

/*!
	\brief
	Attempt to make a container for a user at the given path, succeeds if a container already exists at the path
 */
- (void)makeContainerForUser:(NSString *)user atPath:(NSString *)path handler:(void (^)(BOOL (^)(NSError **)))handler;
/*!
	\brief
	Delete the container, subsequently completing writes will fail when they attempt to swap
 */
- (void)removeContainerForUser:(NSString *)user atPath:(NSString *)path handler:(void (^)(BOOL (^)(NSError **)))handler;
/*!
	\brief
	List the contents of a container
 */
- (void)listContentsOfContainerForUser:(NSString *)user atPath:(NSString *)path handler:(void (^)(NSArray * (^)(NSError **)))handler;

/*!
	\brief
	Requesting an input stream should take a snapshot of the data, it can be implemented as copy-on-read or copy-on-write, so long as the data the stream returns is an atomic copy of the object at the time of the request.
 */
- (NSInputStream *)readStreamForObjectWithUser:(NSString *)user path:(NSString *)path error:(NSError **)errorRef;
/*!
	\brief
	When the stream is closed the data will be made available to other clients for reading.
 */
- (NSOutputStream *)writeStreamForObjectWithUser:(NSString *)user path:(NSString *)path error:(NSError **)errorRef;

@end
