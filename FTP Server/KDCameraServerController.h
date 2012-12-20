//
//  KDCameraServerController.h
//  Camera Server
//
//  Created by Keith Duncan on 17/12/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"

#import "AFVirtualFileSystem.h"

@interface KDCameraServerController : NSObject <AFHTTPServerRenderer>

- (id)initWithFileSystem:(id <AFVirtualFileSystem>)fileSystem;

@end
