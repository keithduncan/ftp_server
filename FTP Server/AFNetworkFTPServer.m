//
//  AFNetworkFTPServer.m
//  FTP Server
//
//  Created by Keith Duncan on 06/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkFTPServer.h"

#import <netdb.h>
#import <getopt.h>

#import "AFNetworkFTPConnection.h"
#import "AFNetworkFTPMessage.h"

@implementation AFNetworkFTPServer

static NSString *const AFNetworkFTPConnectionUserKey = @"AFNetworkFTPConnectionUser"; // NSString
static NSString *const AFNetworkFTPConnectionPasswordKey = @"AFNetworkFTPConnectionPassword"; // NSString
static NSString *const AFNetworkFTPConnectionTypeKey = @"AFNetworkFTPConnectionType"; // NSString
static NSString *const AFNetworkFTPConnectionBinaryKey = @"AFNetworkFTPConnectionBinary"; // NSString
static NSString *const AFNetworkFTPConnectionWorkingDirectoryPath = @"AFNetworkFTPConnectionWorkingDirectory"; // NSString (Relative Path)

static NSString *_AFNetworkFTPServerLoginContext = @"_AFNetworkFTPServerLoginInitialContext";
static NSString *_AFNetworkFTPServerMainContext = @"_AFNetworkFTPServerMainContext";

@synthesize fileSystem=_fileSystem;

+ (id)server {
	return [[[self alloc] initWithEncapsulationClass:[AFNetworkFTPConnection class]] autorelease];
}

- (void)dealloc {
	[_fileSystem release];
	
	[super dealloc];
}

- (void)configureLayer:(AFNetworkFTPConnection *)layer {
	[super configureLayer:layer];
	
	NSDictionary *defaultProperties = [NSDictionary dictionaryWithObjectsAndKeys:
									   @"anonymous", AFNetworkFTPConnectionUserKey,
									   @"A", AFNetworkFTPConnectionTypeKey,
									   (id)kCFBooleanFalse, AFNetworkFTPConnectionBinaryKey,
									   @"/", AFNetworkFTPConnectionWorkingDirectoryPath,
									   nil];
	[defaultProperties enumerateKeysAndObjectsUsingBlock:^ (id key, id obj, BOOL *stop) {
		[layer setUserInfoValue:obj forKey:key];
	}];
	
	[layer setDefaultMessageFunction:(NSString * (*)(NSUInteger))&AFNetworkFTPMessageForReplyCode];
	
	[layer writeReply:AFNetworkFTPReplyCodeServiceReadyForNewUser message:nil readLine:&_AFNetworkFTPServerLoginContext];
}

- (NSString *)_resolvePath:(NSString *)encodedPath relativeToConnectionAndReplyIfCant:(AFNetworkFTPConnection *)connection {
	NSString *decodedPath = [self _decodePath:encodedPath];
	
	NSArray *decodedPathComponents = [decodedPath pathComponents];
	if ([decodedPathComponents count] == 0) {
		[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:@"path not given" readLine:&_AFNetworkFTPServerMainContext];
		return nil;
	}
	
	NSInteger indexOfTilde = [decodedPathComponents indexOfObject:@"~"];
	if (indexOfTilde != NSNotFound && indexOfTilde != 0) {
		[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:@"home relative reference must be the first path component" readLine:&_AFNetworkFTPServerMainContext];
		return nil;
	}
	
	NSString *firstDecodedPathComponent = decodedPathComponents[0];
	
	if ([firstDecodedPathComponent isEqualToString:@"/"]) {
		return decodedPath;
	}
	
	if ([firstDecodedPathComponent isEqualToString:@"~"]) {
		NSString *user = [connection userInfoValueForKey:AFNetworkFTPConnectionUserKey];
		if (user == nil) {
			[connection writeReply:AFNetworkFTPReplyCodeNotLoggedIn message:@"cannot resolve home folder without user" readLine:&_AFNetworkFTPServerMainContext];
			return nil;
		}
		NSArray *remainingPathComponents = [decodedPathComponents subarrayWithRange:NSMakeRange(1, [decodedPathComponents count] - 1)];
		return [NSString pathWithComponents:[@[ @"/", @"Users", user ] arrayByAddingObjectsFromArray:remainingPathComponents]];
	}
	
	NSString *currentWorkingDirectory = [connection userInfoValueForKey:AFNetworkFTPConnectionWorkingDirectoryPath];
	return [currentWorkingDirectory stringByAppendingPathComponent:decodedPath];
}

- (NSString *)_decodePath:(NSString *)path {
	NSMutableString *decodedPath = [[path mutableCopy] autorelease];
	[decodedPath replaceOccurrencesOfString:@"\0" withString:@"\n" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [decodedPath length])];
	return decodedPath;
}

- (NSString *)_encodePath:(NSString *)path {
	NSMutableString *encodedPath = [[path mutableCopy] autorelease];
	[encodedPath replaceOccurrencesOfString:@"\n" withString:@"\0" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [encodedPath length])];
	return encodedPath;
}

- (void)_setWorkingDirectoryPath:(NSString *)workingDirectoryPath forConnection:(AFNetworkFTPConnection *)connection {
	NSParameterAssert([workingDirectoryPath hasPrefix:@"/"]);
	[connection setUserInfoValue:workingDirectoryPath forKey:AFNetworkFTPConnectionWorkingDirectoryPath];
}

- (AFVirtualFileSystemResponse *)_executeFileSystemRequest:(AFVirtualFileSystemRequest *)request authenticate:(BOOL)authenticate forConnection:(AFNetworkFTPConnection *)connection error:(NSError **)errorRef {
	id <AFVirtualFileSystem> fileSystem = self.fileSystem;
	if (fileSystem == nil) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedString(@"No file system is mounted", @"AFNetworkFTPServer no file system mounted error description"),
			};
			*errorRef = [NSError errorWithDomain:AFCoreNetworkingBundleIdentifier code:AFNetworkErrorUnknown userInfo:errorInfo];
		}
		return nil;
	}
	
	do {
		if (!authenticate) {
			break;
		}
		
		NSString *user = [connection userInfoValueForKey:AFNetworkFTPConnectionUserKey], *password = [connection userInfoValueForKey:AFNetworkFTPConnectionPasswordKey];
		if (user == nil || password == nil) {
			break;
		}
		
		request.credentials = [NSURLCredential credentialWithUser:user password:password persistence:NSURLCredentialPersistenceNone];
	} while (0);
	
	return [fileSystem executeRequest:request error:errorRef];
}

- (NSSet *)_executeListRequest:(NSString *)encodedPathname forConnection:(AFNetworkFTPConnection *)connection {
	if ([encodedPathname length] != 0) {
		/*
			Note
			
			should return metadata about the named file in LIST format, instead we reject these requests for now
		 */
		[connection writeReply:AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported message:nil readLine:&_AFNetworkFTPServerMainContext];
		return nil;
	}
	
	NSString *workingDirectory = [connection userInfoValueForKey:AFNetworkFTPConnectionWorkingDirectoryPath];
	AFVirtualFileSystemRequestRead *listRequest = [[[AFVirtualFileSystemRequestRead alloc] initWithPath:workingDirectory] autorelease];
	
	NSError *listError = nil;
	AFVirtualFileSystemResponse *listResponse = [self _executeFileSystemRequest:listRequest authenticate:YES forConnection:connection error:&listError];
	if (listResponse == nil) {
		[self _writeReply:connection forListContentsOfContainer:workingDirectory error:listError];
		return nil;
	}
	
	if (listResponse.node.nodeType != AFVirtualFileSystemNodeTypeContainer) {
		NSError *error = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNotContainer userInfo:nil];
		[self _writeReply:connection forListContentsOfContainer:workingDirectory error:error];
		return nil;
	}
	
	return listResponse.body;
}

- (void)_writeReply:(AFNetworkFTPConnection *)connection forListContentsOfContainer:(NSString *)pathname error:(NSError *)error {
	NSString *message = nil;
	
	if ([[error domain] isEqualToString:AFVirtualFileSystemErrorDomain]) {
		switch ([error code]) {
			case AFVirtualFileSystemErrorCodeNoNodeExists:
			{
				message = [NSString stringWithFormat:@"%@: no such directory", pathname];
				break;
			}
			case AFVirtualFileSystemErrorCodeNotContainer:
			{
				message = [NSString stringWithFormat:@"%@: not a directory", pathname];
				break;
			}
		}
	}
	
	if (message == nil) {
		NSString *failureReason = ([error localizedFailureReason] ? : [NSString stringWithFormat:@"unknown failure, underlying error %@ %ld", [error domain], (long)[error code]]);
		message = [NSString stringWithFormat:@"%@: %@", pathname, failureReason];
	}
	
	[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:message readLine:&_AFNetworkFTPServerMainContext];
}

- (void)_reportDataError:(AFNetworkFTPConnection *)connection error:(NSError *)error {
	if ([[error domain] isEqualToString:AFNetworkFTPErrorDomain]) {
		if ([error code] == AFNetworkFTPErrorCodeNoDataServer) {
			[connection writeReply:AFNetworkFTPReplyCodeRequestedActionAborted message:@"data connection must be established first using PASV or PORT" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		if ([error code] == AFNetworkFTPErrorCodeDataAlreadyEnqueued) {
			[connection writeReply:AFNetworkFTPReplyCodeRequestedActionAborted message:@"data connection already established, wait for the first operation to complete" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
	}
	
	[connection writeReply:AFNetworkFTPReplyCodeRequestedActionAborted message:@"unknown data connection error" readLine:&_AFNetworkFTPServerMainContext];
}

- (void)_writeDataReply:(AFNetworkFTPConnection *)connection bodyStream:(NSInputStream *)bodyStream {
	[connection writeReply:AFNetworkFTPReplyCodeAboutToOpenDataConnection message:nil readLine:NULL];
	
	NSError *writeError = nil;
	BOOL write = [connection writeFirstDataServerConnectionFromReadStream:bodyStream error:&writeError];
	if (!write) {
		[self _reportDataError:connection error:writeError];
		return;
	}
	
#warning needs to write a response on the control channel after the data transfer is complete
}

- (void)_readDataRequest:(AFNetworkFTPConnection *)connection bodyStream:(NSOutputStream *)bodyStream {
	[connection writeReply:AFNetworkFTPReplyCodeAboutToOpenDataConnection message:nil readLine:NULL];
	
	NSError *readError = nil;
	BOOL read = [connection readFirstDataServerConnectionToWriteStream:bodyStream error:&readError];
	if (!read) {
		[self _reportDataError:connection error:readError];
		return;
	}
	
#warning needs to write a response on the control channel after the data transfer is complete
}

- (void)connection:(AFNetworkFTPConnection *)connection didWriteReply:(NSData *)reply context:(void *)context {
	fprintf(stderr, "< %s", [[[[NSString alloc] initWithData:reply encoding:NSASCIIStringEncoding] autorelease] UTF8String]);
}

- (void)connection:(AFNetworkFTPConnection *)connection didReadLine:(NSString *)line context:(void *)context {
	fprintf(stderr, "> %s\n", [line UTF8String]);
	
	__block BOOL didParse = NO;
	void (^tryParseCommand)(NSString *, void (^)(NSString *)) = ^ void (NSString *command, void (^parse)(NSString *parameter)) {
		if (didParse) {
			return;
		}
		
		NSRange commandRange = [line rangeOfString:command options:(NSCaseInsensitiveSearch | NSAnchoredSearch)];
		if (commandRange.location == NSNotFound) {
			return;
		}
		
		didParse = YES;
		
		NSString *parameter = [line substringFromIndex:NSMaxRange(commandRange)];
		if ([parameter hasPrefix:@" "]) {
			parameter = [parameter substringFromIndex:1];
		}
		
		parse(parameter);
	};
	
	tryParseCommand(@"USER", ^ (NSString *parameter) {
		NSString *username = parameter;
		if ([username length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"user parameter not supplied" readLine:&_AFNetworkFTPServerLoginContext];
			return;
		}
		
		BOOL usernameOkay = YES;
		if (!usernameOkay) {
			[connection writeReply:AFNetworkFTPReplyCodeNotLoggedIn message:nil readLine:&_AFNetworkFTPServerLoginContext];
			return;
		}
		
		[connection setUserInfoValue:username forKey:AFNetworkFTPConnectionUserKey];
		
		BOOL usernameSufficient = YES;
		if (!usernameSufficient) {
			[connection writeReply:AFNetworkFTPReplyCodeUsernameOkayNeedPassword message:nil readLine:&_AFNetworkFTPServerLoginContext];
			return;
		}
		
		[connection writeReply:AFNetworkFTPReplyCodeUserLoggedIn message:nil readLine:&_AFNetworkFTPServerMainContext];
		return;
	});
	
	tryParseCommand(@"PASS", ^ (NSString *parameter) {
		NSString *password = parameter;
		if ([password length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"pass parameter not supplied" readLine:&_AFNetworkFTPServerLoginContext];
			return;
		}
		
		BOOL passwordOkay = YES;
		if (!passwordOkay) {
			[connection writeReply:AFNetworkFTPReplyCodeNotLoggedIn message:nil readLine:&_AFNetworkFTPServerLoginContext];
			return;
		}
		
		[connection setUserInfoValue:password forKey:AFNetworkFTPConnectionPasswordKey];
		
		[connection writeReply:AFNetworkFTPReplyCodeUserLoggedIn message:nil readLine:&_AFNetworkFTPServerMainContext];
		return;
	});
	
	tryParseCommand(@"TYPE", ^ (NSString *typeCode) {
		if ([typeCode length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"type parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		BOOL binaryOn = NO;
		if ([typeCode caseInsensitiveCompare:@"A"] == NSOrderedSame ||
			[typeCode caseInsensitiveCompare:@"A N"] == NSOrderedSame) {
			binaryOn = NO;
		}
		else if ([typeCode caseInsensitiveCompare:@"I"] == NSOrderedSame ||
				 [typeCode caseInsensitiveCompare:@"L 8"] == NSOrderedSame) {
			binaryOn = YES;
		}
		else {
			[connection writeReply:AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported message:@"type parameter not supported" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		[connection setUserInfoValue:typeCode forKey:AFNetworkFTPConnectionTypeKey];
		[connection setUserInfoValue:[NSNumber numberWithBool:binaryOn] forKey:AFNetworkFTPConnectionBinaryKey];
		
		[connection writeReply:AFNetworkFTPReplyCodeCommandOK message:nil readLine:&_AFNetworkFTPServerMainContext];
	});
	
	/*
		Note
		
		legacy commands
		STRU, MODE <http://cr.yp.to/ftp/type.html>
		ALLO <http://cr.yp.to/ftp/stor.html>
	 */
	tryParseCommand(@"STRU", ^ (NSString *parameter) {
		if ([parameter caseInsensitiveCompare:@"F"] != NSOrderedSame) {
			[connection writeReply:AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported message:nil readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		[connection writeReply:AFNetworkFTPReplyCodeCommandOK message:nil readLine:&_AFNetworkFTPServerMainContext];
	});
	tryParseCommand(@"MODE", ^ (NSString *parameter) {
		if ([parameter caseInsensitiveCompare:@"S"] != NSOrderedSame) {
			[connection writeReply:AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported message:nil readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		[connection writeReply:AFNetworkFTPReplyCodeCommandOK message:nil readLine:&_AFNetworkFTPServerMainContext];
	});
	tryParseCommand(@"ALLO", ^ (NSString *parameter) {
		[connection writeReply:AFNetworkFTPReplyCodeCommandNotNeeded message:nil readLine:&_AFNetworkFTPServerMainContext];
	});
	
	tryParseCommand(@"SYST", ^ (NSString *parameter) {
		/*
			Note
			
			this is a magic value recommended by <http://cr.yp.to/ftp/syst.html>
		 */
		[connection writeReply:AFNetworkFTPReplyCodeSystemName message:@"UNIX Type: L8" readLine:&_AFNetworkFTPServerMainContext];
	});
	
	tryParseCommand(@"FEAT", ^ (NSString *parameter) {
		[connection writeReply:AFNetworkFTPReplyCodeCommandNoFeatures message:nil readLine:&_AFNetworkFTPServerMainContext];
	});
	
	void (^parsePwdCommand)(NSString *) = ^ (NSString *parameter) {
		NSString *workingDirectoryPath = [connection userInfoValueForKey:AFNetworkFTPConnectionWorkingDirectoryPath];
		
		NSMutableString *encodedPath = [[[self _encodePath:workingDirectoryPath] mutableCopy] autorelease];
		[encodedPath replaceOccurrencesOfString:@"\"" withString:@"\"\"" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [encodedPath length])];
		
		[connection writeReply:AFNetworkFTPReplyCodePathnameCreated message:[NSString stringWithFormat:@"\"%@\"", encodedPath] readLine:&_AFNetworkFTPServerMainContext];
	};
	tryParseCommand(@"PWD", parsePwdCommand);
	tryParseCommand(@"XPWD", parsePwdCommand);
	
	void (^parseCwdCommand)(NSString *) = ^ (NSString *encodedPathname) {
		if ([encodedPathname length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"dirname parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *resolvedPath = [self _resolvePath:encodedPathname relativeToConnectionAndReplyIfCant:connection];
		if (resolvedPath == nil) {
			return;
		}
		
		AFVirtualFileSystemRequestRead *readRequest = [[[AFVirtualFileSystemRequestRead alloc] initWithPath:resolvedPath] autorelease];
		
		NSError *listError = nil;
		AFVirtualFileSystemResponse *listResponse = [self _executeFileSystemRequest:readRequest authenticate:YES forConnection:connection error:&listError];
		if (listResponse == nil) {
			[self _writeReply:connection forListContentsOfContainer:resolvedPath error:listError];
			return;
		}
		
		if (listResponse.node.nodeType != AFVirtualFileSystemNodeTypeContainer) {
			NSError *error = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNotContainer userInfo:nil];
			[self _writeReply:connection forListContentsOfContainer:resolvedPath error:error];
			return;
		}
		
		[self _setWorkingDirectoryPath:resolvedPath forConnection:connection];
		[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionOK message:nil readLine:&_AFNetworkFTPServerMainContext];
	};
	tryParseCommand(@"CWD", parseCwdCommand);
	tryParseCommand(@"XCWD", parseCwdCommand);
	
	void (^parseCdupCommand)(NSString *parameter) = ^ (NSString *parameter) {
		if ([parameter length] != 0) {
			[connection writeReply:AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported message:nil readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *connectionWorkingDirectory = [connection userInfoValueForKey:AFNetworkFTPConnectionWorkingDirectoryPath];
		connectionWorkingDirectory = [connectionWorkingDirectory stringByDeletingLastPathComponent];
		[self _setWorkingDirectoryPath:connectionWorkingDirectory forConnection:connection];
		
		[connection writeReply:AFNetworkFTPReplyCodeCommandOK message:nil readLine:&_AFNetworkFTPServerMainContext];
	};
	tryParseCommand(@"CDUP", parseCdupCommand);
	tryParseCommand(@"XCUP", parseCdupCommand);
	
	void (^parseMkdCommand)(NSString *) = ^ (NSString *encodedPathname) {
		if ([encodedPathname length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"directory parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *resolvedPath = [self _resolvePath:encodedPathname relativeToConnectionAndReplyIfCant:connection];
		if (resolvedPath == nil) {
			return;
		}
		
		AFVirtualFileSystemRequestCreate *createRequest = [[[AFVirtualFileSystemRequestCreate alloc] initWithPath:resolvedPath nodeType:AFVirtualFileSystemNodeTypeContainer] autorelease];
		
		NSError *createError = nil;
		AFVirtualFileSystemResponse *createResponse = [self _executeFileSystemRequest:createRequest authenticate:YES forConnection:connection error:&createError];
		if (createResponse == nil) {
			do {
				if ([[createError domain] isEqualToString:AFVirtualFileSystemErrorDomain]) {
					// Node already exists but it is of the correct type, so the create operation succeeds
					if ([createError code] == AFVirtualFileSystemErrorCodeNodeExists) {
						break;
					}
					
					if ([createError code] == AFVirtualFileSystemErrorCodeNoNodeExists) {
						[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"path prefix doesn't exist"] readLine:&_AFNetworkFTPServerMainContext];
						return;
					}
					
					// A path component of the object path minus last path component isn't a Container
					if ([createError code] == AFVirtualFileSystemErrorCodeNotContainer) {
						[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"path prefix doesn't specify a directory"] readLine:&_AFNetworkFTPServerMainContext];
						return;
					}
				}
				
				// Unknown error
				[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"couldn't create directory, underlying error %@ %ld", [createError domain], (long)[createError code]] readLine:&_AFNetworkFTPServerMainContext];
				return;
			} while (0);
		}
		
		NSMutableString *encodedPath = [NSMutableString stringWithString:[self _encodePath:resolvedPath]];
		[encodedPath replaceOccurrencesOfString:@"\"" withString:@"\"\"" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [encodedPath length])];
		
		[connection writeReply:AFNetworkFTPReplyCodePathnameCreated message:[NSString stringWithFormat:@"\"%@\"", encodedPath] readLine:&_AFNetworkFTPServerMainContext];
	};
	tryParseCommand(@"MKD", parseMkdCommand);
	tryParseCommand(@"XMKD", parseMkdCommand);
	
	tryParseCommand(@"PASV", ^ (NSString *parameter) {
		if ([parameter length] != 0) {
			[connection writeReply:AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported message:nil readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		[connection closeDataServer];
		
		uint16_t h1 = 0, h2 = 0, h3 = 0, h4 = 0;
		uint16_t p1 = 0, p2 = 0;
		
		/*
			Note
			
			1. convert the binary address to ascii numeric, discarding the port of the original address
			2. convert the ascii numeric + port zero to binary address
			3. bind a socket to this address, if bind fails because the address is in use (race condition), goto 2
			4. check the address family of the socket address from step 2
			4.1. if the address is IPv4 convert the address to decimal and return in the PASV reply
			4.2. if the address is IPv6 return 127,555,555,555,p1,p2 in the PASV reply
		 */
		
		do {
			CFDataRef controlConnectionLocalAddress = (CFDataRef)[(AFNetworkSocket *)connection localAddress];
			
			CFRetain(controlConnectionLocalAddress);
			
			char nodename[NI_MAXHOST];
			int controlConnectionGetnameinfoError = getnameinfo((struct sockaddr const *)CFDataGetBytePtr(controlConnectionLocalAddress), (socklen_t)CFDataGetLength(controlConnectionLocalAddress), nodename, sizeof(nodename)/sizeof(*nodename), NULL, 0, NI_NUMERICHOST);
			
			CFRelease(controlConnectionLocalAddress);
			
			if (controlConnectionGetnameinfoError != 0) {
				break;
			}
			
		ConvertNodenameToBinary:;
			struct addrinfo hints = {
				.ai_flags = AI_PASSIVE,
			};
			
			struct addrinfo *addrinfo = NULL;
			int convertNodenameToBinaryError = getaddrinfo(nodename, "0", &hints, &addrinfo);
			if (convertNodenameToBinaryError != 0) {
				break;
			}
			
			NSData *newDataServerSocketAddress = [NSData dataWithBytes:addrinfo->ai_addr length:addrinfo->ai_addrlen];
			freeaddrinfo(addrinfo);
			
			NSError *openSocketError = nil;
			AFNetworkSocket *openSocket = [connection openDataServerWithAddress:newDataServerSocketAddress error:&openSocketError];
			if (openSocket == nil) {
				if ([[openSocketError domain] isEqualToString:AFCoreNetworkingBundleIdentifier] && [openSocketError code] == AFNetworkSocketErrorListenerOpenAddressAlreadyUsed) {
					goto ConvertNodenameToBinary;
				}
				
				break;
			}
			
			CFDataRef dataServerLocalAddress = (CFDataRef)[openSocket localAddress];
			
			CFRetain(dataServerLocalAddress);
			
			struct sockaddr_storage *dataServerLocalAddressStorage = (struct sockaddr_storage *)CFDataGetBytePtr(dataServerLocalAddress);
			socklen_t dataServerLocalAddressLength = (socklen_t)CFDataGetLength(dataServerLocalAddress);
			
			sa_family_t dataServerLocalAddressFamily = dataServerLocalAddressStorage->ss_family;
			
			char dataServerNodename[NI_MAXHOST]; char dataServerServname[NI_MAXSERV];
			int convertDataServerToAsciiError = getnameinfo((struct sockaddr const *)dataServerLocalAddressStorage, dataServerLocalAddressLength, dataServerNodename, sizeof(dataServerNodename)/sizeof(*dataServerNodename), dataServerServname, sizeof(dataServerServname)/sizeof(*dataServerServname), NI_NUMERICHOST | NI_NUMERICSERV);
			
			CFRelease(dataServerLocalAddress);
			
			if (convertDataServerToAsciiError != 0) {
				break;
			}
			
			switch (dataServerLocalAddressFamily) {
				case AF_INET:
				{
					NSArray *numericAddressComponents = [[NSString stringWithCString:dataServerNodename encoding:NSASCIIStringEncoding] componentsSeparatedByString:@"."];
					
					h1 = (uint16_t)[[numericAddressComponents objectAtIndex:0] integerValue];
					h2 = (uint16_t)[[numericAddressComponents objectAtIndex:1] integerValue];;
					h3 = (uint16_t)[[numericAddressComponents objectAtIndex:2] integerValue];;
					h4 = (uint16_t)[[numericAddressComponents objectAtIndex:3] integerValue];;
					break;
				}
				case AF_INET6:
				{
					h1 = 127;
					h2 = h3 = h4 = 555;
					break;
				}
			}
			
			int port = atoi(dataServerServname);
			p2 = port % 256;
			p1 = (port - p2) / 256;
		} while (0);
		if (h1 == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeInternalParsingError message:nil readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *passiveMessage = [NSString stringWithFormat:@"=%hu,%hu,%hu,%hu,%hu,%hu", h1, h2, h3, h4, p1, p2];
		[connection writeReply:AFNetworkFTPReplyCodeEnteringPassiveMode message:passiveMessage readLine:&_AFNetworkFTPServerMainContext];
	});
	
#if 0
	tryParseCommand(@"PORT", ^ (NSString *parameter) {
		
	});
	
	tryParseCommand(@"EPSV", ^ (NSString *parameter) {
		
	});
	
	tryParseCommand(@"EPRT", ^ (NSString *parameter) {
		
	});
#endif
	
	/*
		Note
		
		this uses the EPLF defined here <http://cr.yp.to/ftp/list/eplf.html>
	 */
	tryParseCommand(@"EPLF", ^ (NSString *encodedPathname) {
		NSSet *listResponse = [self _executeListRequest:encodedPathname forConnection:connection];
		if (listResponse == nil) {
			return;
		}
		
		NSMutableData *listData = [NSMutableData data];
		
		BOOL appendedObject = NO;
		
		for (AFVirtualFileSystemNode *currentNode in listResponse) {
			if (appendedObject) {
				[listData appendBytes:"\r\n" length:2];
			}
			appendedObject = YES;
			
			NSMutableData *currentObjectLine = [NSMutableData data];
			[currentObjectLine appendBytes:"+" length:1];
			
			__block BOOL appendedFact = NO;
			void (^appendFact)(NSData *) = ^ void (NSData *fact) {
				if (appendedFact) {
					[currentObjectLine appendBytes:"," length:1];
				}
				appendedFact = YES;
				
				[currentObjectLine appendData:fact];
			};
			
			BOOL isContainer = (currentNode.nodeType == AFVirtualFileSystemNodeTypeContainer);
			if (isContainer) {
				appendFact([NSData dataWithBytes:"/" length:1]); // CWD-able
			}
			else {
				appendFact([NSData dataWithBytes:"r" length:1]); // RETR-able
			}
			
			[currentObjectLine appendBytes:"\t" length:1];
			
			NSString *objectPathname = [currentNode.absolutePath lastPathComponent];
			objectPathname = [self _encodePath:objectPathname];
			[currentObjectLine appendData:[objectPathname dataUsingEncoding:NSUTF8StringEncoding]];
			
			[listData appendData:currentObjectLine];
		}
		
		[self _writeDataReply:connection bodyStream:[NSInputStream inputStreamWithData:listData]];
	});
	
	tryParseCommand(@"LIST", ^ (NSString *parameters) {
		void (^replyUnknownParameters)(void) = ^ {
			[connection writeReply:AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported message:@"unknown parameters" readLine:&_AFNetworkFTPServerMainContext];
		};
		
		NSString *wordSeparator = @" ";
		NSArray *words = [parameters componentsSeparatedByString:wordSeparator];
		
		int argc = (int)[words count] + 1;
		char const **argv = alloca(argc * sizeof(char *));
		
		argv[0] = "\0";
		__block BOOL allWordsIncluded = YES;
		[words enumerateObjectsUsingBlock:^ (NSString *currentWord, NSUInteger currentWordIdx, BOOL *stopEnumeratingWords) {
			NSStringEncoding encoding = NSUTF8StringEncoding;
			if (![currentWord canBeConvertedToEncoding:encoding]) {
				*stopEnumeratingWords = YES;
				
				allWordsIncluded = NO;
				return;
			}
			
			argv[currentWordIdx + 1] = [currentWord cStringUsingEncoding:encoding];
		}];
		if (!allWordsIncluded) {
			replyUnknownParameters();
			return;
		}
		
		/*
			Note
			
			support -a and -l flags
		 */
#warning this isn't thread safe, we need an _r variant as in the GNU C standard library, this already won't work if getopt has already been invoked in this process as it doesn't reset optind
		int option = 0;
		while ((option = getopt(argc, (char *const *)argv, "al")) != -1) {
			switch (option) {
				case 'a':
				{
					break;
				}
				case 'l':
				{
					break;
				}
				case ':':
				case '?':
				default:
				{
					replyUnknownParameters();
					return;
				}
			}
		}
		
		NSSet *listResponse = [self _executeListRequest:nil forConnection:connection];
		if (listResponse == nil) {
			return;
		}
		
		NSDate *fakeLastModifiedDate = [NSDate date];
		NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
		[dateFormatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
		
		NSMutableData *listData = [NSMutableData data];
		
		for (AFVirtualFileSystemNode *currentNode in listResponse) {
			NSMutableData *currentObjectLine = [NSMutableData data];
			
			/*
				Note
				
				we don't actually implement BSD based user permissions
				
				our current file system API doesn't support it either
				
				we default to 'owner' and 'group', deal with it
				
				we also don't support anything other than containers and objects
				if support for links are added in the future support will need to be added here too
			 */
			char const *linePrefix = NULL;
			if (currentNode.nodeType == AFVirtualFileSystemNodeTypeContainer) {
				linePrefix = "drw-r--r-- 1 owner group";
			}
			else if (currentNode.nodeType == AFVirtualFileSystemNodeTypeObject) {
				linePrefix = "-rwxr-xr-x 1 owner group";
			}
			if (linePrefix == NULL) {
				listData = nil;
				break;
			}
			[currentObjectLine appendBytes:linePrefix length:strlen(linePrefix)];
			
			[currentObjectLine appendBytes:" " length:1];
			
			// Note: should include the actual object size and not 0
			char objectSize[13] = {};
			memset(objectSize, ' ', sizeof(objectSize));
			objectSize[12] = '0';
			[currentObjectLine appendBytes:objectSize length:sizeof(objectSize)];
			
			[currentObjectLine appendBytes:" " length:1];
			
			/*
				Note
				
				lie about the modified date because our file sytem API doesn't support reading modification times
				
				rather than statically returning the epoch say it was modified this second
			 */
			NSMutableString *lastModifiedDateString = [NSMutableString string];
			do {
				{
					[dateFormatter setDateFormat:@"MMMM"];
					
					NSMutableString *month = [[[dateFormatter stringForObjectValue:fakeLastModifiedDate] mutableCopy] autorelease];
					
					NSUInteger desiredMonthLength = 3;
					CFStringPad((CFMutableStringRef)month, CFSTR(" "), desiredMonthLength, 0);
					
					[lastModifiedDateString appendString:[month capitalizedString]];
				}
				
				{
					[dateFormatter setDateFormat:@"d"];
					
					NSString *day = [dateFormatter stringForObjectValue:fakeLastModifiedDate];
					
					NSUInteger desiredDayLength = 3;
					NSInteger prefixLength = (desiredDayLength - [day length]);
					if (prefixLength < 0) {
						lastModifiedDateString = nil;
						break;
					}
					
					CFStringPad((CFMutableStringRef)lastModifiedDateString, CFSTR(" "), [lastModifiedDateString length] + prefixLength, 0);
					[lastModifiedDateString appendString:day];
				}
				
				[lastModifiedDateString appendString:@" "];
				
				{
					[dateFormatter setDateFormat:@"HH:mm"];
					NSString *time = [dateFormatter stringFromDate:fakeLastModifiedDate];
					[lastModifiedDateString appendString:time];
				}
			} while (0);
			
			NSData *listModifiedDateStringData = [lastModifiedDateString dataUsingEncoding:NSASCIIStringEncoding];
			if (listModifiedDateStringData == nil) {
				listData = nil;
				break;
			}
			[currentObjectLine appendData:listModifiedDateStringData];
			
			[currentObjectLine appendBytes:" " length:1];
			
			NSString *filename = [currentNode.absolutePath lastPathComponent];
			NSString *encodedFilename = [self _encodePath:filename];
			NSData *encodedFilenameData = [encodedFilename dataUsingEncoding:NSUTF8StringEncoding];
			if (encodedFilenameData == nil) {
				listData = nil;
				break;
			}
			[currentObjectLine appendData:encodedFilenameData];
			
			[currentObjectLine appendBytes:"\r\n" length:2];
			
			[listData appendData:currentObjectLine];
		}
		if (listData == nil) {
			[connection writeReply:AFNetworkFTPReplyCodeRequestedActionAborted message:nil readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		[self _writeDataReply:connection bodyStream:[NSInputStream inputStreamWithData:listData]];
	});
	
	tryParseCommand(@"RETR", ^ (NSString *encodedPathname) {
		if ([encodedPathname length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"filename parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *resolvedPath = [self _resolvePath:encodedPathname relativeToConnectionAndReplyIfCant:connection];
		if (resolvedPath == nil) {
			return;
		}
		
		AFVirtualFileSystemRequestRead *readRequest = [[[AFVirtualFileSystemRequestRead alloc] initWithPath:resolvedPath] autorelease];
		
		NSError *readError = nil;
		AFVirtualFileSystemResponse *readResponse = [self _executeFileSystemRequest:readRequest authenticate:YES forConnection:connection error:&readError];
		if (readResponse == nil) {
			do {
				if ([[readError domain] isEqualToString:AFVirtualFileSystemErrorDomain]) {
					if ([readError code] == AFVirtualFileSystemErrorCodeNoNodeExists) {
						[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"file doesn't exist"] readLine:&_AFNetworkFTPServerMainContext];
						return;
					}
					
					// Node already exists but it is isn't an Object, cannot also create an Object with the same name as the existing Node
					if ([readError code] == AFVirtualFileSystemErrorCodeNotObject) {
						[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"entry at path isn't a file"] readLine:&_AFNetworkFTPServerMainContext];
						return;
					}
				}
				
				// Unknown error
				[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"couldn't read file, underlying error %@ %ld", [readError domain], (long)[readError code]] readLine:&_AFNetworkFTPServerMainContext];
				return;
			} while (0);
		}
		
		NSInputStream *readBody = readResponse.body;
		[self _writeDataReply:connection bodyStream:readBody];
	});
	
	tryParseCommand(@"STOR", ^ (NSString *encodedPathname) {
		if ([encodedPathname length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"filename parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *resolvedPath = [self _resolvePath:encodedPathname relativeToConnectionAndReplyIfCant:connection];
		if (resolvedPath == nil) {
			return;
		}
		
		AFVirtualFileSystemRequestCreate *createRequest = [[[AFVirtualFileSystemRequestCreate alloc] initWithPath:resolvedPath nodeType:AFVirtualFileSystemNodeTypeObject] autorelease];
		
		NSError *createError = nil;
		AFVirtualFileSystemResponse *createResponse = [self _executeFileSystemRequest:createRequest authenticate:YES forConnection:connection error:&createError];
		if (createResponse == nil) {
			do {
				if ([[createError domain] isEqualToString:AFVirtualFileSystemErrorDomain]) {
					// Node already exists but it is of the correct type, so the create operation succeeds
					if ([createError code] == AFVirtualFileSystemErrorCodeNodeExists) {
						break;
					}
					
					if ([createError code] == AFVirtualFileSystemErrorCodeNoNodeExists) {
						[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"path prefix doesn't exist"] readLine:&_AFNetworkFTPServerMainContext];
						return;
					}
					
					// Node already exists but it is isn't an Object, cannot also create an Object with the same name as the existing Node
					if ([createError code] == AFVirtualFileSystemErrorCodeNotObject) {
						[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"file system entry already exists at path and isn't a file"] readLine:&_AFNetworkFTPServerMainContext];
						return;
					}
					
					// A path component of the object path minus last path component isn't a Container
					if ([createError code] == AFVirtualFileSystemErrorCodeNotContainer) {
						[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"path prefix doesn't specify a directory"] readLine:&_AFNetworkFTPServerMainContext];
						return;
					}
				}
				
				// Unknown error
				[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"couldn't create file, underlying error %@ %ld", [createError domain], (long)[createError code]] readLine:&_AFNetworkFTPServerMainContext];
				return;
			} while (0);
		}
		
		AFVirtualFileSystemRequest *writeStreamRequest = [[[AFVirtualFileSystemRequestUpdate alloc] initWithPath:resolvedPath] autorelease];
		
		NSError *writeStreamError = nil;
		AFVirtualFileSystemResponse *writeResponse = [self _executeFileSystemRequest:writeStreamRequest authenticate:YES forConnection:connection error:&writeStreamError];
		if (writeResponse == nil) {
			[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"unknown failure, underlying error %@ %ld", [writeStreamError domain], (long)[writeStreamError code]] readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSOutputStream *writeBody = writeResponse.body;
		[self _readDataRequest:connection bodyStream:writeBody];
	});
	
	void (^parseRmCommand)(NSString *) = ^ (NSString *encodedPathname) {
		if ([encodedPathname length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"filename parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *resolvedPath = [self _resolvePath:encodedPathname relativeToConnectionAndReplyIfCant:connection];
		if (resolvedPath == nil) {
			return;
		}
		
		AFVirtualFileSystemRequestDelete *deleteRequest = [[[AFVirtualFileSystemRequestDelete alloc] initWithPath:resolvedPath] autorelease];
		
		NSError *deleteError = nil;
		AFVirtualFileSystemResponse *deleteResponse = [self _executeFileSystemRequest:deleteRequest authenticate:YES forConnection:connection error:&deleteError];
		if (deleteResponse == nil) {
			do {
				if ([[deleteError domain] isEqualToString:AFVirtualFileSystemErrorDomain]) {
					// Node doesn't exist, we were trying to delete it, so the delete operation succeeds
					if ([deleteError code] == AFVirtualFileSystemErrorCodeNoNodeExists) {
						break;
					}
					
					// Container doesn't exit, we were trying to delete a subpath, so the delete operation succeeds
					if ([deleteError code] == AFVirtualFileSystemErrorCodeNotContainer) {
						break;
					}
				}
				
				[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:[NSString stringWithFormat:@"unknown failure, underlying error %@ %ld", [deleteError domain], (long)[deleteError code]] readLine:&_AFNetworkFTPServerMainContext];
				return;
			} while (0);
		}
		
		[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionOK message:nil readLine:&_AFNetworkFTPServerMainContext];
	};
	tryParseCommand(@"DELE", parseRmCommand);
	tryParseCommand(@"RMD", parseRmCommand);
	
#if 0
	tryParseCommand(@"RNFR", ^ (NSString *paramter) {
		
	});
	
	tryParseCommand(@"RNTO", ^ (NSString *paramter) {
		
	});
#endif
	
	tryParseCommand(@"QUIT", ^ (NSString *parameter) {
		[connection writeReply:AFNetworkFTPReplyCodeServiceClosingControlConnection message:nil readLine:&_AFNetworkFTPServerMainContext];
		
		[connection closeDataServer];
		
		AFNetworkPacketClose *closePacket = [[[AFNetworkPacketClose alloc] init] autorelease];
		[connection performWrite:closePacket withTimeout:-1 context:&_AFNetworkFTPServerMainContext];
	});
	
	tryParseCommand(@"NOOP", ^ (NSString *parameter) {
		[connection writeReply:AFNetworkFTPReplyCodeCommandOK message:nil readLine:&_AFNetworkFTPServerMainContext];
	});
	
	if (didParse) {
		return;
	}
	
	[connection writeReply:AFNetworkFTPReplyCodeCommandNotImplemented message:nil readLine:&_AFNetworkFTPServerMainContext];
}

- (void)connection:(AFNetworkFTPConnection *)connection dataConnectionDidReceiveError:(NSError *)error {
	
}

- (void)networkLayer:(id <AFNetworkTransportLayer>)layer didReceiveError:(NSError *)error {
	[layer close];
}

- (void)connectionDidWriteDataFromReadStream:(AFNetworkFTPConnection *)connection {
	[connection writeReply:AFNetworkFTPReplyCodeServiceClosingDataConnection message:nil readLine:&_AFNetworkFTPServerMainContext];
	[connection closeDataServer];
}

- (void)connectionDidReadDataToWriteStream:(AFNetworkFTPConnection *)connection {
	[connection writeReply:AFNetworkFTPReplyCodeServiceClosingDataConnection message:nil readLine:&_AFNetworkFTPServerMainContext];
	[connection closeDataServer];
}

@end
