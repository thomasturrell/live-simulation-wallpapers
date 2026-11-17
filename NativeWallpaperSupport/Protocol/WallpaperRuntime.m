// Private ABI details based on Aerial (MIT). See LICENSE.
#import "WallpaperRuntime.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <xpc/xpc.h>

static Class contextWrapper;
static Class snapshotWrapper;
static ptrdiff_t contextOffset;
static ptrdiff_t surfaceOffset;

static ptrdiff_t payloadOffset(Class cls, const char *name, size_t payloadSize) {
    if (!cls || class_getInstanceSize(cls) != 2 * sizeof(void *)) return 0;
    Ivar ivar = class_getInstanceVariable(cls, name);
    ptrdiff_t offset = ivar ? ivar_getOffset(ivar) : sizeof(void *);
    if (offset != sizeof(void *) || offset + payloadSize > class_getInstanceSize(cls)) return 0;
    return offset;
}

BOOL LifeLoadWallpaperABI(void) {
    static dispatch_once_t once;
    static BOOL ready;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit",
                             RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return;
        contextWrapper = NSClassFromString(@"WallpaperRemoteContextXPC");
        snapshotWrapper = NSClassFromString(@"WallpaperSnapshotXPC");
        contextOffset = payloadOffset(contextWrapper, "box", sizeof(uint32_t));
        surfaceOffset = payloadOffset(snapshotWrapper, "rawValue", sizeof(IOSurfaceRef));
        SEL encode = @selector(encodeWithCoder:);
        Method method = class_getInstanceMethod(snapshotWrapper, encode);
        if (!contextOffset || !surfaceOffset || !method || !NSClassFromString(@"WallpaperSettingsViewModelsXPC")) return;

        // Aerial found the private snapshot encoder omits the surface for some
        // NSXPCEncoder variants. Restrict the adapter to that class in this process.
        const SEL encodeSurface = NSSelectorFromString(@"encodeXPCObject:forKey:");
        void (*original)(id, SEL, NSCoder *) = (void *)method_getImplementation(method);
        id block = ^(id object, NSCoder *coder) {
            IOSurfaceRef surface = *(IOSurfaceRef *)((uint8_t *)(__bridge void *)object + surfaceOffset);
            if (surface && [coder respondsToSelector:encodeSurface]) {
                @try {
                    ((void (*)(id, SEL, xpc_object_t, NSString *))objc_msgSend)(
                        coder, encodeSurface, IOSurfaceCreateXPCObject(surface), @"surface");
                    return;
                } @catch (NSException *exception) {
                    NSLog(@"Wallpaper extension: snapshot encoding: %@", exception.reason);
                }
            }
            original(object, encode, coder);
        };
        class_replaceMethod(snapshotWrapper, encode, imp_implementationWithBlock(block), method_getTypeEncoding(method));
        ready = YES;
    });
    return ready;
}

id LifeMakeWallpaperContext(CALayer *layer, CGFloat scale, NSNumber *display) {
    Class contextClass = NSClassFromString(@"CAContext");
    SEL create = NSSelectorFromString(@"remoteContextWithOptions:");
    if (![contextClass respondsToSelector:create]) return nil;
    NSMutableDictionary *options = [@{@"contentsScale": @(scale)} mutableCopy];
    if (display) options[@"displayId"] = display;
    @try {
        id context = ((id (*)(id, SEL, NSDictionary *))objc_msgSend)(contextClass, create, options);
        [context setValue:layer forKey:@"layer"];
        if ([context respondsToSelector:NSSelectorFromString(@"setContentsScale:")]) {
            [context setValue:@(scale) forKey:@"contentsScale"];
        }
        return context;
    } @catch (NSException *exception) {
        NSLog(@"Wallpaper extension: remote layer: %@", exception.reason);
        return nil;
    }
}

id LifeWrapWallpaperContext(id context) {
    if (!contextOffset) return nil;
    SEL selector = NSSelectorFromString(@"contextId");
    if (![context respondsToSelector:selector]) return nil;
    uint32_t token = ((uint32_t (*)(id, SEL))objc_msgSend)(context, selector);
    if (!token) return nil;
    id result = class_createInstance(contextWrapper, 0);
    if (!result) return nil;
    *(uint32_t *)((uint8_t *)(__bridge void *)result + contextOffset) = token;
    return result;
}

id LifeWrapWallpaperSnapshot(IOSurfaceRef surface) {
    if (!surfaceOffset) return nil;
    id result = class_createInstance(snapshotWrapper, 0);
    if (!result) return nil;
    *(IOSurfaceRef *)((uint8_t *)(__bridge void *)result + surfaceOffset) = (IOSurfaceRef)CFRetain(surface);
    return result;
}
