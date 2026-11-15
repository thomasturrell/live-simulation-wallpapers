#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN
BOOL LifeLoadWallpaperABI(void);
id _Nullable LifeMakeWallpaperContext(CALayer *layer, CGFloat scale, NSNumber *_Nullable display);
id _Nullable LifeWrapWallpaperContext(id context);
id _Nullable LifeWrapWallpaperSnapshot(IOSurfaceRef surface);
NS_ASSUME_NONNULL_END
