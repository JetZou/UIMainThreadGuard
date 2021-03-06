//
//  PSPDFUIKitMainThreadGuard.m
//  YoluAddressBook
//
//  Created by Jet on 13-12-15.
//  Copyright (c) 2013年 Yolu. All rights reserved.
//

#import "HaloUIKitMainThreadGuard.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Compile-time selector checks.
#if DEBUG
#define PROPERTY(propName) NSStringFromSelector(@selector(propName))
#else
#define PROPERTY(propName) @#propName
#endif

// A better assert. NSAssert is too runtime dependant, and assert() doesn't log.
// http://www.mikeash.com/pyblog/friday-qa-2013-05-03-proper-use-of-asserts.html
// Accepts both:
// - PSPDFAssert(x > 0);
// - PSPDFAssert(y > 3, @"Bad value for y");
#define PSPDFAssert(expression, ...) \
do { if(!(expression)) { \
NSLog(@"%@", [NSString stringWithFormat: @"Assertion failure: %s in %s on line %s:%d. %@", #expression, __PRETTY_FUNCTION__, __FILE__, __LINE__, [NSString stringWithFormat:@"" __VA_ARGS__]]); \
abort(); }} while(0)

@implementation HaloUIKitMainThreadGuard
///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Helper for Swizzling

BOOL HaloReplaceMethodWithBlock(Class c, SEL origSEL, SEL newSEL, id block) {
    PSPDFAssert(c && origSEL && newSEL && block);
    Method origMethod = class_getInstanceMethod(c, origSEL);
    const char *encoding = method_getTypeEncoding(origMethod);
    
    // Add the new method.
    IMP impl = imp_implementationWithBlock(block);
    if (!class_addMethod(c, newSEL, impl, encoding)) {
        NSLog(@"Failed to add method: %@ on %@", NSStringFromSelector(newSEL), c);
        return NO;
    }else {
        // Ensure the new selector has the same parameters as the existing selector.
        Method newMethod = class_getInstanceMethod(c, newSEL);
        PSPDFAssert(strcmp(method_getTypeEncoding(origMethod), method_getTypeEncoding(newMethod)) == 0, @"Encoding must be the same.");
        
        // If original doesn't implement the method we want to swizzle, create it.
        if (class_addMethod(c, origSEL, method_getImplementation(newMethod), encoding)) {
            class_replaceMethod(c, newSEL, method_getImplementation(origMethod), encoding);
        }else {
            method_exchangeImplementations(origMethod, newMethod);
        }
    }
    return YES;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Tracks down calls to UIKit from a Thread other than Main

static void HaloAssertIfNotMainThread(void) {
    PSPDFAssert(NSThread.isMainThread, @"\nERROR: All calls to UIKit need to happen on the main thread. You have a bug in your code. Use dispatch_async(dispatch_get_main_queue(), ^{ ... }); if you're unsure what thread you're in.\n\nBreak on HaloAssertIfNotMainThread to find out where.\n\nStacktrace: %@", [NSThread callStackSymbols]);
}

// This installs a small guard that checks for the most common threading-errors in UIKit.
// This won't really slow down performance but still only is compiled in DEBUG versions of PSPDFKit.
// @note No private API is used here.
void HaloUIKitMainThreadGuardFunc(void) {
    @autoreleasepool {
        for (NSString *selStr in @[PROPERTY(setNeedsLayout), PROPERTY(setNeedsDisplay), PROPERTY(setNeedsDisplayInRect:)]) {
            SEL selector = NSSelectorFromString(selStr);
            SEL newSelector = NSSelectorFromString([NSString stringWithFormat:@"pspdf_%@", selStr]);
            if ([selStr hasSuffix:@":"]) {
                HaloReplaceMethodWithBlock(UIView.class, selector, newSelector, ^(__unsafe_unretained UIView *_self, CGRect r) {
                    HaloAssertIfNotMainThread();
                    ((void ( *)(id, SEL, CGRect))objc_msgSend)(_self, newSelector, r);
                });
            }else {
                HaloReplaceMethodWithBlock(UIView.class, selector, newSelector, ^(__unsafe_unretained UIView *_self) {
                    HaloAssertIfNotMainThread();
                    ((void ( *)(id, SEL))objc_msgSend)(_self, newSelector);
                });
            }
        }
    }
}
@end
