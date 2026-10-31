// SPDX-License-Identifier: Apache-2.0
// Isolate ChemDraw's installed preview components from the interactive editor.
// No vendor binaries are copied into the add-in. The adapter never creates
// window controllers or sends save events to the interactive ChemDraw process.
#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#include <dlfcn.h>
#include <stdexcept>
#include <unistd.h>

@protocol CFMDocumentPDF <NSObject>
- (instancetype)initWithDocument:(NSDocument *)document;
- (void)setIsPaginated:(BOOL)paginated;
- (NSData *)generatePDFData:(NSError **)error;
@end

static void require(bool condition, NSString *message) {
    if (!condition) throw std::runtime_error(message.UTF8String ?: "ChemDraw preview failed");
}

static void validateCode(NSURL *url) {
    SecStaticCodeRef code = nullptr;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &code);
    if (status == errSecSuccess) {
        status = SecStaticCodeCheckValidity(code, kSecCSStrictValidate | kSecCSCheckNestedCode, nullptr);
        CFRelease(code);
    }
    require(status == errSecSuccess, [NSString stringWithFormat:@"ChemDraw preview component failed signature validation (%d): %@", (int)status, url.lastPathComponent]);
}

static int render(NSString *application, NSString *source) {
    NSURL *app = [NSURL fileURLWithPath:application isDirectory:YES];
    validateCode(app);
    NSArray<NSString *> *libraries = @[
        @"Contents/Frameworks/CoreChemistry.framework/Versions/A/CoreChemistry",
        @"Contents/Frameworks/ChemDrawBase.framework/Versions/A/ChemDrawBase",
        @"Contents/PlugIns/QuickLook.appex/Contents/Frameworks/ChemDrawSDK.framework/Versions/A/ChemDrawSDK"
    ];
    void *sdk = nullptr;
    for (NSString *relative in libraries) {
        NSURL *library = [app URLByAppendingPathComponent:relative];
        validateCode(library);
        sdk = dlopen(library.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        const char *reason = sdk ? nullptr : dlerror();
        require(sdk != nullptr, reason ? @(reason) : @"Could not load ChemDraw preview components");
    }
    // The installed Quick Look SDK initialises its own font, preference and
    // chemistry services. This exported function returns a context pointer;
    // no C++ object layouts or return-value conventions are reproduced here.
    using Context = void *(*)();
    auto context = reinterpret_cast<Context>(dlsym(sdk, "_ZN11ChemDrawSDK18ChemDrawSDKContext16GetSharedContextEv"));
    require(context != nullptr, @"This ChemDraw SDK has no preview context entry point");
    require(context() != nullptr, @"ChemDraw could not initialise its preview context");

    Class documentClass = NSClassFromString(@"CDDocument"), generatorClass = NSClassFromString(@"CDPDFGenerator");
    require([documentClass isSubclassOfClass:NSDocument.class] &&
            [generatorClass instancesRespondToSelector:@selector(initWithDocument:)] &&
            [generatorClass instancesRespondToSelector:@selector(setIsPaginated:)] &&
            [generatorClass instancesRespondToSelector:@selector(generatePDFData:)],
            @"This ChemDraw SDK has no document PDF preview interface");
    NSError *error = nil;
    NSURL *url = [NSURL fileURLWithPath:source];
    NSData *input = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
    require(input != nil && input.length > 0 && input.length <= 48 * 1024 * 1024,
            error.localizedDescription ?: @"The captured ChemDraw source is empty or too large");
    bool cdx = input.length >= 8 && memcmp(input.bytes, "VjCD0100", 8) == 0;
    NSDocument *document = [[documentClass alloc] initWithContentsOfURL:url
                                                              ofType:cdx ? @"com.revvity.cdx" : @"com.revvity.cdxml"
                                                               error:&error];
    require(document != nil, error.localizedDescription ?: @"ChemDraw could not read the captured structure");
    id<CFMDocumentPDF> generator = [(id<CFMDocumentPDF>)[generatorClass alloc] initWithDocument:document];
    [generator setIsPaginated:NO];
    NSData *pdf = [generator generatePDFData:&error];
    require(pdf.length >= 5 && pdf.length <= 48 * 1024 * 1024 && memcmp(pdf.bytes, "%PDF-", 5) == 0,
            error.localizedDescription ?: @"ChemDraw returned an invalid PDF preview");
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
    CGPDFDocumentRef preview = CGPDFDocumentCreateWithProvider(provider);
    bool valid = preview && CGPDFDocumentGetNumberOfPages(preview) == 1;
    if (preview) CGPDFDocumentRelease(preview);
    CGDataProviderRelease(provider);
    require(valid, @"ChemDraw did not return a single-page PDF preview");
    require([input isEqualToData:[NSData dataWithContentsOfURL:url]], @"The captured ChemDraw source changed during preview generation");
    [NSFileHandle.fileHandleWithStandardOutput writeData:pdf];
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        // Also bound failures inside vendor code which do not return to Cocoa.
        alarm(20);
        try {
            @try {
                require(argc == 3, @"Usage: chemdraw-renderer application-path captured-source-path");
                return render(@(argv[1]), @(argv[2]));
            } @catch (NSException *exception) {
                throw std::runtime_error(exception.reason.UTF8String ?: "ChemDraw preview exception");
            }
        } catch (const std::exception &error) {
            fprintf(stderr, "%s\n", error.what());
        } catch (...) {
            fprintf(stderr, "ChemDraw preview component failed\n");
        }
    }
    return 1;
}
