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

- (NSString *)_decodePath:(NSString *)encodedPathname relativeTo:(NSString *)currentWorkingDirectory {
	NSMutableString *decodedPathname = [[encodedPathname mutableCopy] autorelease];
	[decodedPathname replaceOccurrencesOfString:@"\0" withString:@"\012" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [decodedPathname length])];
	
	NSString *newPathname = nil;
	if (![decodedPathname hasPrefix:@"/"]) {
		newPathname = [currentWorkingDirectory stringByAppendingPathComponent:decodedPathname];
	}
	else {
		newPathname = decodedPathname;
	}
	return newPathname;
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
		
		NSRange commandRange = [line rangeOfString:command options:NSCaseInsensitiveSearch];
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
		
		[connection writeReply:AFNetworkFTPReplyCodeUserLoggedIn message:nil readLine:&_AFNetworkFTPServerMainContext];
		return;
	});
	
	tryParseCommand(@"TYPE", ^ (NSString *typeCode) {
		BOOL acceptTypeCode = NO, binaryOn = NO;
		if ([typeCode caseInsensitiveCompare:@"A"] == NSOrderedSame ||
			[typeCode caseInsensitiveCompare:@"A N"] == NSOrderedSame) {
			acceptTypeCode = YES;
			binaryOn = NO;
		}
		else if ([typeCode caseInsensitiveCompare:@"I"] == NSOrderedSame ||
				 [typeCode caseInsensitiveCompare:@"L 8"] == NSOrderedSame) {
			acceptTypeCode = YES;
			binaryOn = YES;
		}
		else {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"type parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		if (!acceptTypeCode) {
			[connection writeReply:AFNetworkFTPReplyCodeCommandNotImplemented message:nil readLine:&_AFNetworkFTPServerMainContext];
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
		NSString *connectionWorkingDirectory = [connection userInfoValueForKey:AFNetworkFTPConnectionWorkingDirectoryPath];
		
		NSMutableString *printableConnectionWorkingDirectory = [[connectionWorkingDirectory mutableCopy] autorelease];
		[printableConnectionWorkingDirectory replaceOccurrencesOfString:@"\"" withString:@"\"\"" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [printableConnectionWorkingDirectory length])];
		[printableConnectionWorkingDirectory replaceOccurrencesOfString:@"\012" withString:@"\0" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [printableConnectionWorkingDirectory length])];
		
		[connection writeReply:AFNetworkFTPReplyCodePathnameCreated message:[NSString stringWithFormat:@"\"%@\" Created", printableConnectionWorkingDirectory] readLine:&_AFNetworkFTPServerMainContext];
	};
	tryParseCommand(@"PWD", parsePwdCommand);
	tryParseCommand(@"XPWD", parsePwdCommand);
	
	void (^parseCwdCommand)(NSString *) = ^ (NSString *encodedPathname) {
		if ([encodedPathname length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"dirname parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		id <AFNetworkVirtualFileSystem> fileSystem = self.fileSystem;
		if (fileSystem == nil) {
			[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:@"no file system mounted" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *user = [connection userInfoValueForKey:AFNetworkFTPConnectionUserKey];
		NSString *decodedPath = [self _decodePath:encodedPathname relativeTo:[connection userInfoValueForKey:AFNetworkFTPConnectionWorkingDirectoryPath]];
		
		[fileSystem listContentsOfContainerForUser:user atPath:decodedPath handler:^ void (NSArray * (^completionProvider)(NSError **)) {
			NSError *contentsError = nil;
			NSArray *contents = completionProvider(&contentsError);
			if (contents == nil) {
				NSString *message = nil;
				
				if ([[contentsError domain] isEqualToString:AFNetworkVirtualFileSystemErrorDomain]) {
					switch ([contentsError code]) {
						case AFNetworkVirtualFileSystemErrorCodeNoEntry:
						{
							message = [NSString stringWithFormat:@"%@: no such directory", encodedPathname];
							break;
						}
						case AFNetworkVirtualFileSystemErrorCodeNotContainer:
						{
							message = [NSString stringWithFormat:@"%@: not a directory", encodedPathname];
							break;
						}
					}
				}
				
				if (message == nil) {
					NSString *failureReason = ([contentsError localizedFailureReason] ? : [NSString stringWithFormat:@"unknown failure, underlying error code %ld", (long)[contentsError code]]);
					message = [NSString stringWithFormat:@"%@: %@", encodedPathname, failureReason];
				}
				
				[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:message readLine:&_AFNetworkFTPServerMainContext];
				return;
			}
			
			[connection setUserInfoValue:decodedPath forKey:AFNetworkFTPConnectionWorkingDirectoryPath];
			[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionOK message:nil readLine:&_AFNetworkFTPServerMainContext];
		}];
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
		[connection setUserInfoValue:connectionWorkingDirectory forKey:AFNetworkFTPConnectionWorkingDirectoryPath];
		
		[connection writeReply:AFNetworkFTPReplyCodeCommandOK message:nil readLine:&_AFNetworkFTPServerMainContext];
	};
	tryParseCommand(@"CDUP", parseCdupCommand);
	tryParseCommand(@"XCUP", parseCdupCommand);
	
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
#endif
	
#if 0
	tryParseCommand(@"EPSV", ^ (NSString *parameter) {
		
	});
	
	tryParseCommand(@"EPRT", ^ (NSString *parameter) {
		
	});
#endif
	
#if 0
	tryParseCommand(@"LIST", ^ (NSString *parameter) {
		
	});
#endif
	
#if 0
	tryParseCommand(@"RETR", ^ (NSString *parameter) {
		
	});
#endif
	
	tryParseCommand(@"STOR", ^ (NSString *encodedPathname) {
		if ([encodedPathname length] == 0) {
			[connection writeReply:AFNetworkFTPReplyCodeParameterSyntaxError message:@"filename parameter not supplied" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		id <AFNetworkVirtualFileSystem> fileSystem = self.fileSystem;
		if (fileSystem == nil) {
			[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:@"no file system mounted" readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		NSString *user = [connection userInfoValueForKey:AFNetworkFTPConnectionUserKey];
		NSString *decodedPath = [self _decodePath:encodedPathname relativeTo:[connection userInfoValueForKey:AFNetworkFTPConnectionWorkingDirectoryPath]];
		
		NSError *writeStreamError = nil;
		NSOutputStream *writeStream = [fileSystem writeStreamForObjectWithUser:user path:decodedPath error:&writeStreamError];
		if (writeStream == nil) {
			NSString *message = [NSString stringWithFormat:@"unknown failure, underlying error code %ld", (long)[writeStreamError code]];
			[connection writeReply:AFNetworkFTPReplyCodeRequestedFileActionError message:message readLine:&_AFNetworkFTPServerMainContext];
			return;
		}
		
		[connection writeReply:AFNetworkFTPReplyCodeAboutToOpenDataConnection mark:nil readLine:NULL];
		
		[connection readFirstDataServerConnectionToWriteStream:writeStream];
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
	
	if (!didParse) {
		[connection writeReply:AFNetworkFTPReplyCodeCommandNotImplemented message:nil readLine:&_AFNetworkFTPServerMainContext];
	}
}

- (void)connection:(AFNetworkFTPConnection *)connection dataConnectionDidReceiveError:(NSError *)error {
	
}

- (void)connectionDidReadDataToWriteStream:(AFNetworkFTPConnection *)connection {
	
}

@end
