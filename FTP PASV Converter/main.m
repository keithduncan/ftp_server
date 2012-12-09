//
//  main.m
//  FTP PASV Converter
//
//  Created by Keith Duncan on 09/12/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

static void Usage(int argc, char const **argv)
{
	fprintf(stderr, "Usage: %s h1,h2,h3,h4,p1,p2\n", argv[0]);
}

int main(int argc, char const **argv)
{
	@autoreleasepool {
		if (argc <= 1) {
			Usage(argc, argv);
			return -1;
		}
		
		char const *pasvStringBytes = argv[1];
		NSString *pasvString = [NSString stringWithCString:pasvStringBytes encoding:NSUTF8StringEncoding];
		
		NSArray *components = [pasvString componentsSeparatedByString:@","];
		if ([components count] != 6) {
			Usage(argc, argv);
			return -1;
		}
		
		int h1 = 0, h2 = 0, h3 = 0, h4 = 0;
		
		int hIdx = 0;
		h1 = [components[hIdx++] intValue];
		h2 = [components[hIdx++] intValue];
		h3 = [components[hIdx++] intValue];
		h4 = [components[hIdx++] intValue];
		
		int p1 = 0, p2 = 0;
		
		int pIdx = hIdx;
		p1 = [components[pIdx++] intValue];
		p2 = [components[pIdx++] intValue];
		
		int port = ((p1 * 256) + p2);
		
		printf("%d.%d.%d.%d %d", h1, h2, h3, h4, port);
	}
    return 0;
}

