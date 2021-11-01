#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "zipzap/zipzap.h"

#ifdef DEBUG
	#define LOG(LogContents, ...) NSLog((@"myinst [DEBUG]: %s:%d " LogContents), __FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
	#define LOG(...)
#endif
#define kIdentifierKey @"CFBundleIdentifier"
#define kAppType @"User"
#define kAppTypeKey @"ApplicationType"
#define kRandomLength 6

#define DPKG_PATH "/var/lib/dpkg/info/git.shin.myinst.list"

static const NSString *kRandomAlphabet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

typedef enum {
	AppInstExitCodeSuccess = 0x0,
	AppInstExitCodeInject,
	AppInstExitCodeZip,
	AppInstExitCodeMalformed,
	AppInstExitCodeFileSystem,
	AppInstExitCodeRuntime,
	AppInstExitCodeUnknown
} AppInstExitCode;

// MobileInstallation for iOS 5 to 7
typedef void (*MobileInstallationCallback)(CFDictionaryRef information);
typedef int (*MobileInstallationInstall)(CFStringRef path, CFDictionaryRef parameters, MobileInstallationCallback callback, CFStringRef backpath);
#define MI_PATH "/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation"

// LSApplicationWorkspace for iOS 8
@interface LSApplicationWorkspace : NSObject

+ (id)defaultWorkspace;
- (BOOL)installApplication:(NSURL *)path withOptions:(NSDictionary *)options;
- (BOOL)uninstallApplication:(NSString *)identifier withOptions:(NSDictionary *)options;

@end

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		printf("myinst (My Installer)\n");
		printf("Copyright (C) 2020 Tachibana Shin(たちばな　しん)");
		printf("** PLEASE DO NOT USE MYINST FOR PIRACY **\n");
		if (access(DPKG_PATH, F_OK) == -1) {
			printf("You seem to have installed appinst from a Cydia/APT repository that is not tachibana-shin.github.io (package ID git.shin.myinst).\n");
			printf("If someone other than Karen/あけみ or Linus Yang (laokongzi) is taking credit for the development of this tool, they are likely lying.\n");
			printf("Please only download appinst from the official repository to ensure file integrity and reliability.\n");
		}

		// Clean up temporary directory
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *workPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"git.shin.myinst"];
		if ([fileManager fileExistsAtPath:workPath]) {
			if (![fileManager removeItemAtPath:workPath error:nil]) {
				printf("Failed to remove temporary path: %s, ignoring.\n", [workPath UTF8String]);
			} else {
				printf("Cleaning up temporary files…\n");
			}
		}

		// Check arguments
		if (argc != 2) {
			printf("Usage: myinst <path to ipa file>\n");
			return AppInstExitCodeUnknown;
		}
		
		// Check file existence
		NSString *filePath = [NSString stringWithUTF8String:argv[1]];
		if (![fileManager fileExistsAtPath:filePath]) {
			printf("The file \"%s\" could not be found. Perhaps you made a typo?\n", [filePath UTF8String]);
			return AppInstExitCodeFileSystem;
		}

		// Resolve app identifier
		NSString *appIdentifier = nil;
		ZZArchive *archive = [ZZArchive archiveWithURL:[NSURL fileURLWithPath:filePath] error:nil];
		for (ZZArchiveEntry* entry in archive.entries) {
			NSArray *components = [[entry fileName] pathComponents];
			NSUInteger count = components.count;
			NSString *firstComponent = [components objectAtIndex:0];
			if ([firstComponent isEqualToString:@"/"]) {
				firstComponent = [components objectAtIndex:1];
				count -= 1;
			}
			if (count == 3 && [firstComponent isEqualToString:@"Payload"] &&
				[components.lastObject isEqualToString:@"Info.plist"]) {
				NSData *fileData = [entry newDataWithError:nil];
				if (fileData == nil) {
					printf("Unable to read the specified IPA file.\n");
					return AppInstExitCodeZip;
				}
				NSError *error = nil;
				NSPropertyListFormat format;
				NSDictionary * dict = (NSDictionary *) [NSPropertyListSerialization propertyListWithData:fileData
					options:NSPropertyListImmutable format:&format error:&error];
				if (dict == nil) {
					printf("The specified IPA file contains a malformed Info.plist.\n");
					return AppInstExitCodeMalformed;
				}
				appIdentifier = [dict objectForKey:kIdentifierKey];
				break;
			}
		}
		if (appIdentifier == nil) {
			printf("Failed to resolve app identifier.\n");
			return AppInstExitCodeMalformed;
		}

		// Copy file to temporary directiory
		if (![fileManager createDirectoryAtPath:workPath withIntermediateDirectories:YES attributes:nil error:NULL]) {
			printf("Failed to create working path.\n");
			return AppInstExitCodeFileSystem;
		}
		NSMutableString *randomString = [NSMutableString stringWithCapacity:kRandomLength];
		for (int i = 0; i < kRandomLength; i++) {
			[randomString appendFormat: @"%C", [kRandomAlphabet characterAtIndex:arc4random_uniform([kRandomAlphabet length])]];
		}
		NSString *installName = [NSString stringWithFormat:@"tmp.%@.install.ipa", randomString];
		NSString *installPath = [workPath stringByAppendingPathComponent:installName];
		if ([fileManager fileExistsAtPath:installPath]) {
			if (![fileManager removeItemAtPath:installPath error:nil]) {
				printf("Failed to remove temporary files.\n");
				return AppInstExitCodeFileSystem;
			}
		}
		if (![fileManager copyItemAtPath:filePath toPath:installPath error:nil]) {
			printf("Failed to copy files to working path.\n");
			return AppInstExitCodeFileSystem;
		}

		// Call system API to install app
		printf("Installing \"%s\"…\n", [appIdentifier UTF8String]);
		BOOL isInstalled = NO;
		if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
			// Use LSApplicationWorkspace
			Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
			if (LSApplicationWorkspace_class == nil) {
				printf("Failed to get class: LSApplicationWorkspace\n");
				return AppInstExitCodeRuntime;
			}
			LSApplicationWorkspace *workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
			if (workspace == nil) {
				printf("Failed to get the default workspace.\n");
				return AppInstExitCodeRuntime;
			}

			// Install file
			NSDictionary *options = [NSDictionary dictionaryWithObject:appIdentifier forKey:kIdentifierKey];
			@try {
				if ([workspace installApplication:[NSURL fileURLWithPath:installPath] withOptions:options]) {
					isInstalled = YES;
				}
			} @catch (NSException *e) {}
		} else {
			// Use MobileInstallationInstall
			void *image = dlopen(MI_PATH, RTLD_LAZY);
			if (image == NULL) {
				printf("Failed to retrieve MobileInstallation.\n");
				return AppInstExitCodeRuntime;
			}
			MobileInstallationInstall installHandle = (MobileInstallationInstall) dlsym(image, "MobileInstallationInstall");
			if (installHandle == NULL) {
				printf("Failed to retrieve the function MobileInstallationInstall.\n");
				return AppInstExitCodeRuntime;
			}

			// Install file
			NSDictionary *options = [NSDictionary dictionaryWithObject:kAppType forKey:kAppTypeKey];
			if (installHandle((__bridge CFStringRef) installPath, (__bridge CFDictionaryRef) options, NULL, (__bridge CFStringRef) installPath) == 0) {
				isInstalled = YES;
			}
		}

		// Clean up
		if ([fileManager fileExistsAtPath:installPath] &&
			[fileManager isDeletableFileAtPath:installPath]) {
			[fileManager removeItemAtPath:installPath error:nil];
		}

		// Exit
		if (isInstalled) {
			printf("Successfully installed \"%s\"!\n", [appIdentifier UTF8String]);
			return AppInstExitCodeSuccess;
		}
		
		printf("Failed to install \"%s\".\n", [appIdentifier UTF8String]);
		return AppInstExitCodeUnknown;
	}
}
