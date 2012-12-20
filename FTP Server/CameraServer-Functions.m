//
//  CameraServer-Functions.m
//  Camera Server
//
//  Created by Keith Duncan on 17/12/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "CameraServer-Functions.h"

NSData *CameraServerContentsOfInputStream(NSInputStream *stream, NSError **errorRef) {
	NSMutableData *bodyData = [NSMutableData data];
	
	[stream open];
	NSCParameterAssert([stream streamStatus] == NSStreamStatusOpen);
	
	while ([stream streamStatus] == NSStreamStatusOpen) {
		NSUInteger initialLength = [bodyData length];
		
		size_t bufferSize = 1024;
		[bodyData increaseLengthBy:bufferSize];
		
		uint8_t *buffer = [bodyData mutableBytes] + initialLength;
		
		NSInteger readLength = [stream read:buffer maxLength:bufferSize];
		[bodyData setLength:(initialLength + readLength)];
	}
	if ([stream streamStatus] == NSStreamStatusError) {
		if (errorRef != NULL) {
			*errorRef = [stream streamError];
		}
		return NULL;
	}
	
	return bodyData;
}

NSString *CameraServerContentTypeForFileSystemPath(NSString *path) {
	NSString *contentType = @"application/octet-stream";
	
	do {
		NSString *fileExtension = path.pathExtension;
		if (fileExtension == nil) {
			break;
		}
		
		NSString *type = (NSString *)[NSMakeCollectable(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)fileExtension, NULL)) autorelease];
		if (type == nil) {
			break;
		}
		
		NSString *mimeType = [NSMakeCollectable(UTTypeCopyPreferredTagWithClass((CFStringRef)type, kUTTagClassMIMEType)) autorelease];
		if (mimeType == nil) {
			break;
		}
		
		contentType = mimeType;
	} while (0);
	
	return contentType;
}
