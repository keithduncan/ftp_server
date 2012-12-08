//
//  AFNetworkVirtualFileSystem.h
//  FTP Server
//
//  Created by Keith Duncan on 20/11/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFVirtualFileSystem.h"

NSString *const AFVirtualFileSystemErrorDomain = @"com.thirty-three.corenetworking.vfs";

@interface AFVirtualFileSystemNode ()
@property (readwrite, copy, nonatomic) NSString *absolutePath;
@property (readwrite, assign, nonatomic) AFVirtualFileSystemNodeType nodeType;
@end

@implementation AFVirtualFileSystemNode

@synthesize absolutePath=_absolutePath;
@synthesize nodeType=_nodeType;

- (id)initWithAbsolutePath:(NSString *)absolutePath nodeType:(AFVirtualFileSystemNodeType)nodeType {
	self = [self init];
	if (self == nil) return nil;
	
	_absolutePath = [absolutePath copy];
	_nodeType = nodeType;
	
	return self;
}

- (void)dealloc {
	[_absolutePath release];
	
	[super dealloc];
}

@end

@interface AFVirtualFileSystemRequest ()
@property (readwrite, copy, nonatomic) NSString *path;
@end

@implementation AFVirtualFileSystemRequest

@synthesize path=_path;
@synthesize credentials=_credentials;

- (id)initWithPath:(NSString *)path {
	self = [self init];
	if (self == nil) return nil;
	
	_path = [path copy];
	
	return self;
}

- (void)dealloc {
	[_path release];
	[_credentials release];
	
	[super dealloc];
}

@end

@interface AFVirtualFileSystemRequestCreate ()
@property (readwrite, assign, nonatomic) AFVirtualFileSystemNodeType nodeType;
@end

@implementation AFVirtualFileSystemRequestCreate

@synthesize nodeType=_nodeType;

- (id)initWithPath:(NSString *)path nodeType:(AFVirtualFileSystemNodeType)nodeType {
	self = [self initWithPath:path];
	if (self == nil) return nil;
	
	_nodeType = nodeType;
	
	return self;
}

@end

@implementation AFVirtualFileSystemRequestRead

- (id)initWithPath:(NSString *)path {
	return [super initWithPath:path];
}

@end

@implementation AFVirtualFileSystemRequestList

- (id)initWithPath:(NSString *)path {
	return [super initWithPath:path];
}

@end

@implementation AFVirtualFileSystemRequestUpdate

- (id)initWithPath:(NSString *)path {
	return [super initWithPath:path];
}

@end

@implementation AFVirtualFileSystemRequestDelete

- (id)initWithPath:(NSString *)path {
	return [super initWithPath:path];
}

@end
