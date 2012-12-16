//
//  AFVirtualFileSystem.h
//  FTP Server
//
//  Created by Keith Duncan on 20/11/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AFVirtualFileSystemNode;

extern NSString *const AFVirtualFileSystemErrorDomain;

typedef NS_ENUM(NSInteger, AFVirtualFileSystemErrorCode) {
	AFVirtualFileSystemErrorCodeUnknown = 0,
	
	// File System Errors [-1, -99]
	AFVirtualFileSystemErrorCodeNotMounted = -1,
	AFVirtualFileSystemErrorCodeAlreadyMounted = -2,
	AFVirtualFileSystemErrorCodeUnknownRequest = -3,
	AFVirtualFileSystemErrorCodeBusy = -4,
	
	// Node Errors [-100, -199]
	AFVirtualFileSystemErrorCodeNoNodeExists = -100,
	AFVirtualFileSystemErrorCodeNodeExists = -101,
	
	AFVirtualFileSystemErrorCodeNotContainer = -102,
	AFVirtualFileSystemErrorCodeNotObject = -103,
	
	AFVirtualFileSystemErrorCodeContainerNotEmpty = -104,
};

typedef NS_ENUM(NSUInteger, AFVirtualFileSystemNodeType) {
	AFVirtualFileSystemNodeTypeContainer,
	AFVirtualFileSystemNodeTypeObject,
};

/*
	Virtual Node Operations
 */

/*!
	\brief
	File system operations are modelled as CRUD
 */
@interface AFVirtualFileSystemRequest : NSObject

/*!
	\brief
	Designated initialiser.
 */
- (id)initWithPath:(NSString *)path;

/*!
	\brief
	All request types have a target path
 */
@property (readonly, copy, nonatomic) NSString *path;

/*!
	\brief
	Any request type can include authentication
 */
@property (copy, nonatomic) NSURLCredential *credentials;

@end

/*!
	\brief
	Returns success error if the node didn't already exist, if the node exists when this request is performed { AFVirtualFileSystemErrorDomain : AFVirtualFileSystemErrorCodeNodeExists } is returned, if this is an acceptable condition you should detect this error
 */
@interface AFVirtualFileSystemRequestCreate : AFVirtualFileSystemRequest

- (id)initWithPath:(NSString *)path nodeType:(AFVirtualFileSystemNodeType)nodeType;

@property (readonly, assign, nonatomic) AFVirtualFileSystemNodeType nodeType;

@end

/*!
	\brief
	If `path` points to an Object, the body of the response is an `NSInputStream`
	If `path` points to a Container, the response body is an `NSSet` object of the children
 */
@interface AFVirtualFileSystemRequestRead : AFVirtualFileSystemRequest

- (id)initWithPath:(NSString *)path;

@end

/*!
	\brief
	An `NSOutputStream` is returned and upon close the data from it is associated with the Object at `path`
 */
@interface AFVirtualFileSystemRequestUpdate : AFVirtualFileSystemRequest

- (id)initWithPath:(NSString *)path;

@end

/*!
	\brief
	Returns success if the node was deleted, if the node doesn't exist { AFVirtualFileSystemErrorDomain : AFVirtualFileSystemErrorCodeNoNodeExists } is returned, if this is an acceptable condition you must detect this error
	
	\details
	Can fail if
	- the Object doesn't exist
	- the Object is considered open, that is there is a pending output stream close
 */
@interface AFVirtualFileSystemRequestDelete : AFVirtualFileSystemRequest

- (id)initWithPath:(NSString *)path;

@end

#pragma mark -

@interface AFVirtualFileSystemResponse : NSObject

- (id)initWithNode:(AFVirtualFileSystemNode *)node body:(id)body;

@property (readonly, retain, nonatomic) AFVirtualFileSystemNode *node;

@property (readonly, retain, nonatomic) id body;

@end

#pragma mark -

/*!
	\brief
	A hierarchical storage system.
	
	This file system deals in Containers, Objects (akin to Directories and Files in the UNIX file system model) and Metadata.
	
	It can be mapped to a directory structure in the physical file system, or kept completely virtual.
	
	\details
	The path separator is the <slash> as in POSIX.
	
	A conforming virtual file system may operate on the physical file system (deferring to the kernel VFS subsystem), or synthesise a file system from in-memory structures.
	A file system may also act as a facade and issue requests to underlying file system based on the path of the request.
	
	See also `struct vfsops` in <sys/mount.h> for file system ops and `struct vnodeopv_entry_desc` in <Kernel/sys/vnode_if.h> for vnode ops.
 */
@protocol AFVirtualFileSystem <NSObject>

/*!
	\brief
	Should be sent before any requests are sent, no requests should be attempted until this returns YES.
 */
- (BOOL)mount:(NSError **)errorRef;

/*!
	\brief
	If there are any ongoing node requests this should return NO and and error byref.
 */
- (BOOL)unmount:(NSError **)errorRef;

/*!
	\brief
	All node related requests are funneled through this method.
	
	\details
	It is programmer error to execute a request before a file system has been sent -mount: or after it has been sent -unmount:
 */
- (AFVirtualFileSystemResponse *)executeRequest:(AFVirtualFileSystemRequest *)request error:(NSError **)errorRef;

@end

#pragma mark -

/*!
	\brief
	Nodes can be Containers or Objects. Containers have Nodes as children, Objects have data associated with them.
	
	\details
	Node names can be any Unicode character sequence.
	Names from the user should be normalised using Normalization Form C <http://www.unicode.org/reports/tr15/tr15-23.html#Specification> before passing them to the file system for consistent results.
	Names from an API should be uses as-is, for example names from a file system list request.
 */
@interface AFVirtualFileSystemNode : NSObject

/*!
	\brief
	The name of this object can be determined by the `[absolutePath lastPathComponent]`
 */
@property (readonly, copy, nonatomic) NSString *absolutePath;

@property (readonly, assign, nonatomic) AFVirtualFileSystemNodeType nodeType;

@end
