//
//  CameraServer-Functions.h
//  Camera Server
//
//  Created by Keith Duncan on 17/12/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSData *CameraServerContentsOfInputStream(NSInputStream *stream, NSError **errorRef);

extern NSString *CameraServerContentTypeForFileSystemPath(NSString *path);
