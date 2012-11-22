//
//  VirtualFileSystem.h
//  FTP Server
//
//  Created by Keith Duncan on 07/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AFNetworkVirtualFileSystem.h"

@interface AFNetworkInMemoryFileSystem : NSObject <AFNetworkVirtualFileSystem>

@end
