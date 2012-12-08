//
//  AFNetworkFTPServer.m
//  FTP Server
//
//  Created by Keith Duncan on 06/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkFTPServer.h"

#import <netdb.h>

#import "AFNetworkFTPConnection.h"

typedef AFNETWORK_ENUM(NSUInteger, AFNetworkFTPReplyCode) {
	AFNetworkFTPReplyCodeAboutToOpenDataConnection					= 150,
	
	AFNetworkFTPReplyCodeCommandOK									= 200,
	AFNetworkFTPReplyCodeCommandNotNeeded							= 202,
	AFNetworkFTPReplyCodeCommandNoFeatures							= 211,
	AFNetworkFTPReplyCodeSystemName									= 215,
	AFNetworkFTPReplyCodeServiceReadyForNewUser						= 220,
	AFNetworkFTPReplyCodeServiceClosingControlConnection			= 221,
	AFNetworkFTPReplyCodeEnteringPassiveMode						= 227,
	AFNetworkFTPReplyCodeUserLoggedIn								= 230,
	AFNetworkFTPReplyCodeRequestedFileActionOK						= 250,
	AFNetworkFTPReplyCodePathnameCreated							= 257,
	
	AFNetworkFTPReplyCodeUsernameOkayNeedPassword					= 331,
	AFNetworkFTPReplyCodeUsernameOkayNeedAccount					= 332,
	
	AFNetworkFTPReplyCodeCantOpenDataConnection						= 425,
	AFNetworkFTPReplyCodeRequestedActionAborted						= 451,
	
	AFNetworkFTPReplyCodeInternalParsingError						= 500,
	AFNetworkFTPReplyCodeParameterSyntaxError						= 501,
	AFNetworkFTPReplyCodeCommandNotImplemented						= 502,
	AFNetworkFTPReplyCodeBadSequenceOfCommands						= 503,
	AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported	= 504,
	AFNetworkFTPReplyCodeNotLoggedIn								= 530,
	AFNetworkFTPReplyCodeRequestedFileActionError					= 550,
};

static NSString *AFNetworkFTPMessageForReplyCode(AFNetworkFTPReplyCode replyCode) {
	switch (replyCode) {
		case AFNetworkFTPReplyCodeAboutToOpenDataConnection:
			return @"About To Open Data Connection";
			
		case AFNetworkFTPReplyCodeCommandOK:
			return @"OK";
		case AFNetworkFTPReplyCodeCommandNotNeeded:
			return @"Command Not Needed";
		case AFNetworkFTPReplyCodeCommandNoFeatures:
			return @"No Features";
		case AFNetworkFTPReplyCodeSystemName:
			break;
		case AFNetworkFTPReplyCodeServiceReadyForNewUser:
			return @"Service Ready For New User";
		case AFNetworkFTPReplyCodeServiceClosingControlConnection:
			return @"Service Closing Control Connection";
		case AFNetworkFTPReplyCodeEnteringPassiveMode:
			break;
		case AFNetworkFTPReplyCodeUserLoggedIn:
			return @"User Logged In";
		case AFNetworkFTPReplyCodeRequestedFileActionOK:
			return @"Requested File Action OK";
		case AFNetworkFTPReplyCodePathnameCreated:
			break;
			
		case AFNetworkFTPReplyCodeUsernameOkayNeedPassword:
			return @"Username Okay Need Password";
		case AFNetworkFTPReplyCodeUsernameOkayNeedAccount:
			return @"Username Okay Need Account";
			
		case AFNetworkFTPReplyCodeCantOpenDataConnection:
			return @"Can't Open Data Connection";
		case AFNetworkFTPReplyCodeRequestedActionAborted:
			return @"Requested Action Aborted";
			
		case AFNetworkFTPReplyCodeInternalParsingError:
			return @"Internal Parsing Error";
		case AFNetworkFTPReplyCodeParameterSyntaxError:
			return @"Parameter Syntax Error";
		case AFNetworkFTPReplyCodeCommandNotImplemented:
			return @"Command Not Implemented";
		case AFNetworkFTPReplyCodeBadSequenceOfCommands:
			return @"Bad Sequence Of Commands";
		case AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported:
			return @"Command Supported But Parameter Unsupported";
		case AFNetworkFTPReplyCodeNotLoggedIn:
			return @"Not Logged In";
		case AFNetworkFTPReplyCodeRequestedFileActionError:
			return @"Requested File Action Error";
	}
	
	@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"%ld doesn't have a default message", replyCode] userInfo:nil];
}

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

- (void)networkLayerDidOpen:(id <AFNetworkTransportLayer>)layer {
	[super networkLayerDidOpen:layer];
	
	if (![layer isKindOfClass:[AFNetworkFTPConnection class]]) {
		return;
	}
	
	NSDictionary *defaultProperties = [NSDictionary dictionaryWithObjectsAndKeys:
									   @"anonymous", AFNetworkFTPConnectionUserKey,
									   @"A", AFNetworkFTPConnectionTypeKey,
									   (id)kCFBooleanFalse, AFNetworkFTPConnectionBinaryKey,
									   @"/", AFNetworkFTPConnectionWorkingDirectoryPath,
									   nil];
	[defaultProperties enumerateKeysAndObjectsUsingBlock:^ (id key, id obj, BOOL *stop) {
		[(AFNetworkFTPConnection *)layer setUserInfoValue:obj forKey:key];
	}];
	
	[(AFNetworkFTPConnection *)layer setDefaultMessageFunction:(NSString * (*)(NSUInteger))&AFNetworkFTPMessageForReplyCode];
	
	[(AFNetworkFTPConnection *)layer writeReply:AFNetworkFTPReplyCodeServiceReadyForNewUser message:nil readLine:&_AFNetworkFTPServerLoginContext];
}

- (NSString *)_resolvePath:(NSString *)encodedPath relativeToConnectionAndReplyIfCant:(AFNetworkFTPConnection *)connection {
	NSMutableString *decodedPath = [[encodedPath mutableCopy] autorelease];
	[decodedPath replaceOccurrencesOfString:@"\0" withString:@"\012" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [decodedPath length])];
	
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

- (NSString *)_encodePath:(NSString *)path {
	NSMutableString *encodedPath = [[path mutableCopy] autorelease];
	[encodedPath replaceOccurrencesOfString:@"\"" withString:@"\"\"" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [encodedPath length])];
	[encodedPath replaceOccurrencesOfString:@"\012" withString:@"\0" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [encodedPath length])];
	return encodedPath;
}

- (void)_setWorkingDirectoryPath:(NSString *)workingDirectoryPath forConnection:(AFNetworkFTPConnection *)connection {
	NSParameterAssert([workingDirectoryPath hasPrefix:@"/"]);
	[connection setUserInfoValue:workingDirectoryPath forKey:AFNetworkFTPConnectionWorkingDirectoryPath];
}

- (id)_executeFileSystemRequest:(AFVirtualFileSystemRequest *)request authenticate:(BOOL)authenticate forConnection:(AFNetworkFTPConnection *)connection error:(NSError **)errorRef {
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
		
		NSString *encodedPath = [self _encodePath:workingDirectoryPath];
		
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
		
		AFVirtualFileSystemRequestList *listRequest = [[[AFVirtualFileSystemRequestList alloc] initWithPath:resolvedPath] autorelease];
		
		NSError *listError = nil;
		NSSet *listResponse = [self _executeFileSystemRequest:listRequest authenticate:YES forConnection:connection error:&listError];
		if (listResponse == nil) {
			[self _writeReply:connection forListContentsOfContainer:encodedPathname error:listError];
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
		AFVirtualFileSystemNode *create = [self _executeFileSystemRequest:createRequest authenticate:YES forConnection:connection error:&createError];
		if (create == nil) {
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
		
		NSString *encodedPath = [self _encodePath:[create absolutePath]];
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
			int controlConnectionGetnameinfoError = getnameinfo((const struct sockaddr *)CFDataGetBytePtr(controlConnectionLocalAddress), (socklen_t)CFDataGetLength(controlConnectionLocalAddress), nodename, sizeof(nodename)/sizeof(*nodename), NULL, 0, NI_NUMERICHOST);
			
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
			int convertDataServerToAsciiError = getnameinfo((const struct sockaddr *)dataServerLocalAddressStorage, dataServerLocalAddressLength, dataServerNodename, sizeof(dataServerNodename)/sizeof(*dataServerNodename), dataServerServname, sizeof(dataServerServname)/sizeof(*dataServerServname), NI_NUMERICHOST | NI_NUMERICSERV);
			
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
	
	tryParseCommand(@"LIST", ^ (NSString *encodedPathname) {
		if ([encodedPathname length] != 0) {
			/*
				Note
				
				should return metadata about the named file in LIST format, instead we reject these requests for now
			 */
			[connection writeReply:AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported message:nil readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *workingDirectory = [connection userInfoValueForKey:AFNetworkFTPConnectionWorkingDirectoryPath];
		AFVirtualFileSystemRequestList *listRequest = [[[AFVirtualFileSystemRequestList alloc] initWithPath:workingDirectory] autorelease];
		
		NSError *listError = nil;
		NSSet *listResponse = [self _executeFileSystemRequest:listRequest authenticate:YES forConnection:connection error:&listError];
		if (listResponse == nil) {
			[self _writeReply:connection forListContentsOfContainer:encodedPathname error:listError];
			return;
		}
		
		[connection writeReply:AFNetworkFTPReplyCodeAboutToOpenDataConnection mark:nil];
		
		/*
			Note
			
			this uses the EPLF defined here <http://cr.yp.to/ftp/list/eplf.html>
		 */
		
		NSMutableData *listData = [NSMutableData data];
		
		BOOL appendedObject = NO;
		
		for (AFVirtualFileSystemNode *currentNode in listResponse) {
			if (appendedObject) {
				[listData appendBytes:"\015\012" length:2];
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
			[currentObjectLine appendData:[objectPathname dataUsingEncoding:NSASCIIStringEncoding]];
			
			[listData appendData:currentObjectLine];
		}
		
		[connection writeFirstDataServerConnectionFromReadStream:[NSInputStream inputStreamWithData:listData]];
		
#warning should write a reply on the control connection dependent on the close status of the data connection
	});
	
#if 0
	tryParseCommand(@"RETR", ^ (NSString *parameter) {
		
	});
#endif
	
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
		id create = [self _executeFileSystemRequest:createRequest authenticate:YES forConnection:connection error:&createError];
		if (create == nil) {
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
		NSOutputStream *writeStream = [self _executeFileSystemRequest:writeStreamRequest authenticate:YES forConnection:connection error:&writeStreamError];
		if (writeStream == nil) {
			NSString *message = [NSString stringWithFormat:@"unknown failure, underlying error %@ %ld", [writeStreamError domain], (long)[writeStreamError code]];
			[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:message readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		[connection writeReply:AFNetworkFTPReplyCodeAboutToOpenDataConnection mark:nil];
		
		[connection readFirstDataServerConnectionToWriteStream:writeStream];
		
#warning we should write a reply on the control connection dependent on the close status of the data connection
	});
	
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

- (void)connectionDidReadDataToWriteStream:(AFNetworkFTPConnection *)connection {
	
}

- (void)connectionDidWriteDataFromReadStream:(AFNetworkFTPConnection *)connection {
	
}

@end
