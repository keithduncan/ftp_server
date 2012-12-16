//
//  AFNetworkHTTPFileSystemRenderer.h
//  FTP Server
//
//  Created by Keith Duncan on 12/12/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"
#import "AFVirtualFileSystem.h"

@interface AFNetworkHTTPFileSystemRenderer : NSObject <AFHTTPServerRenderer>

- (id)initWithFileSystem:(id <AFVirtualFileSystem>)fileSystem;

@end
