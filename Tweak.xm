#import "Tweak.h"
#import "CC26Preferences/CC26LocalizableManager.h"

#pragma mark - Border radius helpers

static BOOL showBorders = NO;
static BOOL ios18Lightness = YES;
static CGFloat cornerRoundness = 1.0;

static CGFloat getModuleRadius(CGRect bounds, CGFloat multiplier) {
    CGFloat shortSide = MIN(bounds.size.width, bounds.size.height);
    if (shortSide <= 0.0) return 0.0;

    CGFloat radius;
    if (fabs(bounds.size.width - bounds.size.height) < 5.0 && shortSide < 90.0) {
        return shortSide / 2.0;
    } else if (fabs(bounds.size.width - bounds.size.height) < 5.0 && shortSide >= 90.0) {
        radius = shortSide * (30.0 / 152.0) * multiplier;
    } else {
        radius = shortSide * (23.0 / 68.0) * multiplier;
    }
    return MIN(radius, shortSide / 2.0);
}

static UIView *cc26_viewForIvar(UIView *view, const char *name) {
    if (!view) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(view), name);
    return ivar ? object_getIvar(view, ivar) : nil;
}

static void cc26_setContinuousRadius(UIView *view, CGFloat radius) {
    if (!view) return;
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.continuousCorners = YES;
}

static void cc26_setMaterialLightness(UIView *materialView, BOOL enabled) {
    if (!materialView) return;
    UIView *overlay = [materialView viewWithTag:0xCC2618];
    if (enabled && !overlay) {
        overlay = [[UIView alloc] initWithFrame:materialView.bounds];
        overlay.tag = 0xCC2618;
        overlay.userInteractionEnabled = NO;
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [materialView insertSubview:overlay atIndex:0];
    }
    overlay.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    overlay.hidden = !enabled;
}

NSArray *findAllSubviewsOfClass(UIView *view, Class cls) {
    NSMutableArray *result = [NSMutableArray array];
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:cls]) [result addObject:sub];
        [result addObjectsFromArray:findAllSubviewsOfClass(sub, cls)];
    }
    return result;
}

UIView *findSubviewOfClass(UIView *view, Class cls) {
    if ([view isKindOfClass:cls]) return view;
    for (UIView *subview in view.subviews) {
        UIView *match = findSubviewOfClass(subview, cls);
        if (match) return match;
    }
    return nil;
}

#pragma mark - Media module helpers

void adjustLabelFontsInView(UIView *view, BOOL isTitle) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            label.font = [UIFont systemFontOfSize:13.0 weight:isTitle ? UIFontWeightSemibold : UIFontWeightRegular];
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.7;
            label.textAlignment = NSTextAlignmentLeft;
        } else {
            adjustLabelFontsInView(subview, isTitle);
        }
    }
}

#pragma mark - Slider glyph coloring helpers

void colorLayers(NSArray *layers, CGColorRef color) {
    for (CALayer *sublayer in layers) {
        if ([sublayer isMemberOfClass:%c(CAShapeLayer)]) {
            CAShapeLayer *shapelayer = (CAShapeLayer *)sublayer;
            shapelayer.fillColor = color;
            shapelayer.strokeColor = color;
            shapelayer.shadowColor = [UIColor clearColor].CGColor;
        } else if (sublayer.sublayers.count == 0) {
            sublayer.backgroundColor = color;
            sublayer.borderColor = color;
            sublayer.contentsMultiplyColor = color;
            sublayer.shadowColor = [UIColor clearColor].CGColor;
        }
        colorLayers(sublayer.sublayers, color);
    }
}

%group CC26

static BOOL cc26_isInsideCCCompact(UIView *view) {
    BOOL isInsideCC = NO;
    UIView *v = view;
    while (v.superview) {
        if ([v isKindOfClass:%c(CCUIContentModuleContentContainerView)]) {
            isInsideCC = YES;
            break;
        }
        v = v.superview;
    }
    if (!isInsideCC) return NO;
    UIView *ancestor = view;
    while (ancestor) {
        if ([ancestor isKindOfClass:%c(MRUNowPlayingView)]) {
            @try {
                NSInteger layout = [[ancestor valueForKey:@"_layout"] integerValue];
                if (layout == 2 || layout == 1) return NO;
            } @catch (NSException *e) {}
            break;
        }
        ancestor = ancestor.superview;
    }
    return YES;
}

%hook CCUICAPackageDescription
- (NSURL *)packageURL {
    NSURL *packageURL = %orig;
    if (!colorSliderGlyphs) return packageURL;
    if ([packageURL.absoluteString isEqualToString:@"file:///System/Library/ControlCenter/Bundles/DisplayModule.bundle/Brightness.ca/"]) {
        return [NSURL fileURLWithPath:ROOT_PATH_NS(@"/Library/PreferenceBundles/CC26Preferences.bundle/Brightness.ca")];
    }
    if ([packageURL.absoluteString isEqualToString:@"file:///System/Library/PrivateFrameworks/MediaControls.framework/Volume.ca/"]) {
        return [NSURL fileURLWithPath:ROOT_PATH_NS(@"/Library/PreferenceBundles/CC26Preferences.bundle/VolumeBold.ca")];
    }
    return packageURL;
}
%end

%hook CALayer
- (void)setOpacity:(float)opacity {
    if ([self.delegate isKindOfClass:%c(CCUICAPackageView)] || [self.delegate isKindOfClass:%c(UIImageView)]) {
        id controller = [(UIView *)self.delegate _viewControllerForAncestor];
        if ([controller isKindOfClass:%c(CCUIDisplayModuleViewController)] || [controller isKindOfClass:%c(MRUVolumeViewController)]) {
            opacity = opacity > 0 ? 1.0 : opacity;
        }
    }
    %orig(opacity);
}
%end

%hook CCUIContinuousSliderView
%new
- (void)cc26_applyGlyphColor {
    if (!colorSliderGlyphs) return;
    if (!self.window) return;

    static BOOL cc26_isApplyingGlyph = NO;
    if (cc26_isApplyingGlyph) return;
    cc26_isApplyingGlyph = YES;

    UIColor *glyphColor = nil;
    id controller = [self _viewControllerForAncestor];
    if (!controller) { cc26_isApplyingGlyph = NO; return; }

    if ([controller isKindOfClass:%c(CCUIDisplayModuleViewController)]) {
        NSDictionary *brightnessColorDict = [[NSUserDefaults standardUserDefaults] objectForKey:@"brightnessColorDict" inDomain:domain];
        glyphColor = (brightnessColorDict != nil) ? [UIColor colorWithRed:[brightnessColorDict[@"red"] floatValue] green:[brightnessColorDict[@"green"] floatValue] blue:[brightnessColorDict[@"blue"] floatValue] alpha:1.0] : [UIColor colorWithRed:0.96 green:0.81 blue:0.27 alpha:1.00];
    } else if ([controller isKindOfClass:%c(MRUVolumeViewController)] || [controller isKindOfClass:%c(SBElasticVolumeViewController)]) {
        NSDictionary *volumeColorDict = [[NSUserDefaults standardUserDefaults] objectForKey:@"volumeColorDict" inDomain:domain];
        glyphColor = (volumeColorDict != nil) ? [UIColor colorWithRed:[volumeColorDict[@"red"] floatValue] green:[volumeColorDict[@"green"] floatValue] blue:[volumeColorDict[@"blue"] floatValue] alpha:1.0] : [UIColor colorWithRed:0.35 green:0.67 blue:0.88 alpha:1.00];
    }
    if (!glyphColor) { cc26_isApplyingGlyph = NO; return; }

    UIView *packageView = nil;
    const char *ivarName = "_compensatingGlyphView";

    Ivar ivar = class_getInstanceVariable(object_getClass(self), ivarName);
    if (ivar) {
        packageView = object_getIvar(self, ivar);
    }

    if (packageView && glyphColor) {
        if ([packageView isKindOfClass:%c(CCUICAPackageView)]) {
            colorLayers(@[packageView.layer], glyphColor.CGColor);
        } else if ([packageView isKindOfClass:%c(UIImageView)]) {
            [(UIImageView *)packageView setTintColor:glyphColor];
        }
    }
    cc26_isApplyingGlyph = NO;
}
- (void)didMoveToWindow {
    %orig;
    [self cc26_applyGlyphColor];
}
- (void)_applyGlyphState:(id)arg1 performConfiguration:(BOOL)arg2 {
    %orig;
    [self cc26_applyGlyphColor];
}
- (void)_setActiveGlyphView:(id)arg1 {
    %orig;
    [self cc26_applyGlyphColor];
}
- (BOOL)isGroupRenderingRequired {
    return NO;
}
- (NSArray *)punchOutRootLayers {
    return nil;
}
- (NSArray *)punchOutRenderingViews {
    return nil;
}
%end

%hook MRUNowPlayingControlsView
- (void)layoutSubviews {
    %orig;

    BOOL isInsideCC = NO;
    UIView *v = self;
    while (v.superview) {
        if ([v isKindOfClass:%c(CCUIContentModuleContentContainerView)]) {
            isInsideCC = YES;
            break;
        }
        v = v.superview;
    }
    if (!isInsideCC) return;

    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    UIView *placeholder = [self viewWithTag:0xCC26A0];
    UIView *npView = self.superview;
    while (npView && ![npView isKindOfClass:%c(MRUNowPlayingView)]) npView = npView.superview;
    BOOL expanded = W >= 220.0;
    if (!expanded && npView) {
        @try {
            NSInteger layout = [[npView valueForKey:@"_layout"] integerValue];
            expanded = (layout == 2);
        } @catch (NSException *e) {}
    }
    if (expanded) {
        placeholder.hidden = YES;
        UIView *artwork = cc26_viewForIvar(cc26_viewForIvar(self, "_headerView"), "_artworkView");
        if (artwork) artwork.hidden = NO;
        return;
    }

    CGFloat pad = round(W * 0.092);
    CGFloat artSize = mediaArtworkSize >= 0.0 ? mediaArtworkSize : round(W * 0.29);
    CGFloat artXOffset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"artworkX" inDomain:domain] floatValue];
    CGFloat artYOffset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"artworkY" inDomain:domain] floatValue];
    CGFloat titleXOffset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"titleX" inDomain:domain] floatValue];
    CGFloat titleYOffset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"titleY" inDomain:domain] floatValue];
    CGFloat controlsXOffset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"controlsX" inDomain:domain] floatValue];
    CGFloat controlsYOffset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"controlsY" inDomain:domain] floatValue];
    CGFloat airplayXOffset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"airplayX" inDomain:domain] floatValue];
    CGFloat airplayYOffset = [[[NSUserDefaults standardUserDefaults] objectForKey:@"airplayY" inDomain:domain] floatValue];
    CGFloat artX = (mediaArtworkX >= 0.0 ? mediaArtworkX : pad) + artXOffset;
    CGFloat artY = (mediaArtworkY >= 0.0 ? mediaArtworkY : pad) + artYOffset;
    CGRect artFrame = CGRectMake(artX, artY, artSize, artSize);

    UIView *headerView = cc26_viewForIvar(self, "_headerView");
    UIView *artworkView = cc26_viewForIvar(headerView, "_artworkView");
    UIView *routingButton = cc26_viewForIvar(headerView, "_routingButton");
    UIView *labelView = cc26_viewForIvar(headerView, "_labelView");
    UIView *transportView = cc26_viewForIvar(self, "_transportControlsView");

    if (headerView) {
        CGRect frame = CGRectMake(0.0, 0.0, W, round(H * 0.68));
        headerView.translatesAutoresizingMaskIntoConstraints = YES;
        if (!CGRectEqualToRect(headerView.frame, frame)) headerView.frame = frame;
        headerView.clipsToBounds = NO;
    }

    UIView *artworkParent = artworkView.superview ?: headerView;
    if (artworkView && artworkParent) {
        CGRect frame = [self convertRect:artFrame toView:artworkParent];
        artworkView.translatesAutoresizingMaskIntoConstraints = YES;
        if (!CGRectEqualToRect(artworkView.frame, frame)) artworkView.frame = frame;
        artworkView.layer.cornerRadius = round(artSize * 0.25);
        artworkView.layer.cornerCurve = kCACornerCurveContinuous;
        artworkView.clipsToBounds = YES;

        UIImage *artworkImage = nil;
        @try { artworkImage = [artworkView valueForKey:@"artworkImage"]; } @catch (NSException *e) {}
        BOOL hasArtwork = artworkImage != nil;
        if (!placeholder) {
            placeholder = [[UIView alloc] initWithFrame:frame];
            placeholder.tag = 0xCC26A0;
            placeholder.userInteractionEnabled = NO;
            placeholder.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
            placeholder.layer.cornerRadius = round(artSize * 0.25);
            placeholder.layer.cornerCurve = kCACornerCurveContinuous;
            [artworkParent insertSubview:placeholder belowSubview:artworkView];
        }
        placeholder.frame = frame;
        placeholder.layer.cornerRadius = round(artSize * 0.25);
        placeholder.layer.cornerCurve = kCACornerCurveContinuous;
        placeholder.hidden = hasArtwork;
        artworkView.hidden = !hasArtwork;
    }

    CGFloat routeSize = mediaRoutingBtnSize >= 0.0 ? mediaRoutingBtnSize : round(W * 0.22);
    CGFloat routeX = mediaRoutingBtnX >= 0.0 ? mediaRoutingBtnX : W - pad - routeSize;
    CGFloat routeY = mediaRoutingBtnY >= 0.0 ? mediaRoutingBtnY : pad + round((artSize - routeSize) / 2.0);
    CGRect routeFrame = CGRectMake(routeX + airplayXOffset, routeY + airplayYOffset, routeSize, routeSize);
    if (routingButton) {
        UIView *routeParent = routingButton.superview ?: headerView;
        CGRect frame = [self convertRect:routeFrame toView:routeParent];
        routingButton.translatesAutoresizingMaskIntoConstraints = YES;
        if (!CGRectEqualToRect(routingButton.frame, frame)) routingButton.frame = frame;
        routingButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        routingButton.layer.cornerRadius = routeSize / 2.0;
        routingButton.layer.cornerCurve = kCACornerCurveContinuous;
        routingButton.clipsToBounds = YES;
        routingButton.tintColor = [UIColor whiteColor];
        for (UIView *subview in routingButton.subviews) {
            if ([subview isKindOfClass:[UIImageView class]]) ((UIImageView *)subview).tintColor = [UIColor whiteColor];
        }
        for (UIView *duplicate in findAllSubviewsOfClass(headerView, %c(MRUNowPlayingRoutingButton))) {
            if (duplicate != routingButton) duplicate.hidden = YES;
        }
    }

    CGFloat labelY = CGRectGetMaxY(artFrame) + round(H * 0.05) + titleYOffset;
    CGFloat labelH = mediaLabelH >= 0.0 ? mediaLabelH : round(H * 0.20);
    CGFloat labelX = (mediaLabelX >= 0.0 ? mediaLabelX : pad) + titleXOffset;
    CGFloat labelW = mediaLabelW >= 0.0 ? mediaLabelW : W - pad * 2.0;
    if (labelView) {
        CGRect labelFrame = CGRectMake(labelX, mediaLabelY >= 0.0 ? mediaLabelY : labelY, labelW, labelH);
        CGRect frame = [self convertRect:labelFrame toView:labelView.superview ?: headerView];
        labelView.translatesAutoresizingMaskIntoConstraints = YES;
        if (!CGRectEqualToRect(labelView.frame, frame)) labelView.frame = frame;
        labelView.clipsToBounds = YES;
        adjustLabelFontsInView(labelView, NO);
    }

    if (transportView) {
        CGFloat transportH = round(H * 0.22);
        CGRect transportFrame = CGRectMake(pad + controlsXOffset, H - pad - transportH + controlsYOffset, W - pad * 2.0, transportH);
        CGRect frame = [self convertRect:transportFrame toView:transportView.superview ?: self];
        transportView.translatesAutoresizingMaskIntoConstraints = YES;
        if (!CGRectEqualToRect(transportView.frame, frame)) transportView.frame = frame;
        transportView.hidden = NO;
    }
}
%end


%hook CCUIContentModuleContentContainerView
- (void)layoutSubviews {
    %orig;

    BOOL opened = MSHookIvar<BOOL>(self, "_expanded");
    BOOL containsMedia = (findSubviewOfClass(self, %c(MRUNowPlayingView)) != nil);
    BOOL containsSlider = (findSubviewOfClass(self, %c(CCUIContinuousSliderView)) != nil);
    BOOL containsSteppedSlider = (findSubviewOfClass(self, %c(CCUISteppedSliderView)) != nil);
    BOOL containsFocus = (findSubviewOfClass(self, %c(FCUIActivityListContentView)) != nil);
    BOOL containsAnySlider = containsSlider || containsSteppedSlider;

    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    CGFloat minDim = fminf(W, H);

    BOOL isStandaloneSlider = containsAnySlider && !containsMedia;
    NSNumber *roundnessValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"cornerRoundness" inDomain:appearanceDomain];
    CGFloat roundness = roundnessValue ? [roundnessValue floatValue] : 1.0;
    CGFloat radius = opened ? 65.0 : getModuleRadius(self.bounds, roundness);

    BOOL suppressContainerBorder = opened && (containsMedia || isStandaloneSlider || containsFocus);
    self.clipsToBounds = YES;
    cc26_setContinuousRadius(self, radius);
    self.layer.continuousCorners = YES;
    self.layer.borderWidth = (showBorders && !suppressContainerBorder) ? 2.0 : 0.0;
    self.layer.borderColor = self.layer.borderWidth > 0.0 ? [UIColor colorWithWhite:0.5 alpha:0.3].CGColor : nil;
    self.layer.masksToBounds = YES;

    if (containsSlider) {
        NSArray *sliders = findAllSubviewsOfClass(self, %c(CCUIContinuousSliderView));
        for (UIView *slider in sliders) {
            CGFloat sliderRadius = getModuleRadius(slider.bounds, roundness);
            cc26_setContinuousRadius(slider, sliderRadius);
            slider.clipsToBounds = YES;
            slider.layer.borderWidth = (showBorders && isStandaloneSlider) ? 1.0 : 0.0;
            slider.layer.borderColor = slider.layer.borderWidth > 0.0 ? [UIColor colorWithWhite:0.5 alpha:0.3].CGColor : nil;
        }
    }

    if (containsSteppedSlider) {
        NSArray *steppedSliders = findAllSubviewsOfClass(self, %c(CCUISteppedSliderView));
        for (UIView *slider in steppedSliders) {
            CGFloat sliderRadius = getModuleRadius(slider.bounds, roundness);
            cc26_setContinuousRadius(slider, sliderRadius);
            slider.clipsToBounds = YES;
        }
    }

    UIView *moduleMaterial = nil;
    @try { moduleMaterial = [self valueForKey:@"moduleMaterialView"]; } @catch (NSException *e) {}
    if (moduleMaterial) {
        cc26_setContinuousRadius(moduleMaterial, opened ? 65.0 : getModuleRadius(moduleMaterial.bounds, roundness));
        moduleMaterial.clipsToBounds = YES;
        cc26_setMaterialLightness(moduleMaterial, ios18Lightness);
    }
    for (UIView *material in findAllSubviewsOfClass(self, %c(MTMaterialView))) {
        CGFloat materialRadius = getModuleRadius(material.bounds, roundness);
        UIView *ancestor = material.superview;
        while (ancestor && ancestor != self && ![ancestor isKindOfClass:%c(CCUIContinuousSliderView)] && ![ancestor isKindOfClass:%c(CCUISteppedSliderView)]) ancestor = ancestor.superview;
        if ([ancestor isKindOfClass:%c(CCUIContinuousSliderView)] || [ancestor isKindOfClass:%c(CCUISteppedSliderView)]) {
            materialRadius = getModuleRadius(ancestor.bounds, roundness);
            materialRadius = MIN(materialRadius, MIN(material.bounds.size.width, material.bounds.size.height) / 2.0);
        }
        cc26_setContinuousRadius(material, materialRadius);
        material.clipsToBounds = YES;
        cc26_setMaterialLightness(material, ios18Lightness);
    }

    UIView *npv = findSubviewOfClass(self, %c(MRUNowPlayingView));
    if (npv) {
        cc26_setContinuousRadius(npv, opened ? 65.0 : getModuleRadius(npv.bounds, roundness));
        npv.layer.borderWidth = (showBorders && opened) ? 2.0 : 0.0;
        npv.layer.borderColor = npv.layer.borderWidth > 0.0 ? [UIColor colorWithWhite:0.5 alpha:0.3].CGColor : nil;
        npv.layer.masksToBounds = YES;
    }

    UIView *focus = findSubviewOfClass(self, %c(FCUIActivityControl));
    if (focus) {
        cc26_setContinuousRadius(focus, getModuleRadius(focus.bounds, roundness));
        focus.layer.borderWidth = showBorders ? 2.0 : 0.0;
        focus.layer.borderColor = focus.layer.borderWidth > 0.0 ? [UIColor colorWithWhite:0.5 alpha:0.3].CGColor : nil;
        focus.layer.masksToBounds = YES;
    }
}
%end

%hook CCUIModularControlCenterOverlayViewController
- (void)setPresentationState:(NSInteger)state {
    %orig;

    UIView *view = self.view;
    CGFloat iconSize = 14; // Kleinere Icons
    CGFloat buttonPadding = 6; // Button etwas größer für Touchfläche
    CGFloat buttonSize = iconSize + buttonPadding;
    CGFloat yOffset = 23;
    CGFloat safeLeft = view.window.safeAreaInsets.left ?: 36;
    CGFloat safeRight = view.window.safeAreaInsets.right ?: 36;

    if (enableTopButtons) {
        // Plus-Button
        UIButton *plus = [view viewWithTag:999];
        if (!plus) {
            NSDictionary *addColorDict = [[NSUserDefaults standardUserDefaults] objectForKey:@"addButtonColorDict" inDomain:domain];
            UIColor *addColor = (addColorDict != nil) ? [UIColor colorWithRed:[addColorDict[@"red"] floatValue] green:[addColorDict[@"green"] floatValue] blue:[addColorDict[@"blue"] floatValue] alpha:1.0] : [UIColor whiteColor];

            plus = [UIButton buttonWithType:UIButtonTypeSystem];
            plus.tag = 999;

            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:iconSize weight:UIImageSymbolWeightRegular];
            UIImage *plusImage = [[UIImage systemImageNamed:@"plus"] imageByApplyingSymbolConfiguration:config];

            [plus setImage:plusImage forState:UIControlStateNormal];
            plus.tintColor = addColor;
            plus.alpha = 0.0;
            plus.transform = CGAffineTransformMakeScale(0.6, 0.6);
            plus.frame = CGRectMake(safeLeft, yOffset - 10, buttonSize, buttonSize);

            [plus addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
                UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
                [gen impactOccurred];
                [((SpringBoard *)[%c(SpringBoard) sharedApplication]) applicationOpenURL:[NSURL URLWithString:@"prefs:root=ControlCenter&path=CUSTOMIZE_CONTROLS"]];
                NSLog(@"[+] Plus tapped");
            }] forControlEvents:UIControlEventTouchUpInside];

            [view addSubview:plus];
        }

        // Power-Button
        UIButton *power = [view viewWithTag:998];
        if (!power) {
            power = [UIButton buttonWithType:UIButtonTypeSystem];
            power.tag = 998;

            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightMedium];
            UIImage *powerImage = [[UIImage systemImageNamed:@"power" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

            [power setImage:powerImage forState:UIControlStateNormal];
            power.alpha = 0.0;
            power.transform = CGAffineTransformMakeScale(0.6, 0.6);
            power.frame = CGRectMake(view.bounds.size.width - safeRight - buttonSize, yOffset - 10, buttonSize, buttonSize);

            if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){14,0,0}]) {
                UIAction *respringAction = [UIAction actionWithTitle:CC26_LOCALIZABLE(@"Respring")
                                                            image:[UIImage systemImageNamed:@"arrow.clockwise.circle"]
                                                        identifier:nil
                                                            handler:^(__kindof UIAction *action) {
                    pid_t pid;
                    const char *args[] = {"sbreload", NULL};
                    posix_spawn(&pid, ROOT_PATH("/usr/bin/sbreload"), NULL, NULL, (char *const *)args, NULL);
                }];

                UIAction *uicacheAction = [UIAction actionWithTitle:CC26_LOCALIZABLE(@"UICache")
                                                            image:[UIImage systemImageNamed:@"paintbrush.fill"]
                                                        identifier:nil
                                                            handler:^(__kindof UIAction *action) {
                    pid_t pid;
                    const char *args[] = {"uicache", "-a", NULL};
                    posix_spawn(&pid, ROOT_PATH("/usr/bin/uicache"), NULL, NULL, (char *const *)args, NULL);
                }];

                UIAction *userspaceAction = [UIAction actionWithTitle:CC26_LOCALIZABLE(@"Userspace Reboot")
                                                                image:[UIImage systemImageNamed:@"bolt.fill"]
                                                        identifier:nil
                                                            handler:^(__kindof UIAction *action) {
                    pid_t pid;
                    const char *args[] = {"launchctl", "reboot", "userspace", NULL};
                    posix_spawn(&pid, ROOT_PATH("/bin/launchctl"), NULL, NULL, (char *const *)args, NULL);
                }];

                UIMenu *menu = [UIMenu menuWithTitle:CC26_LOCALIZABLE(@"Choose Action")
                                            children:@[respringAction, uicacheAction, userspaceAction]];
                [power setMenu:menu];
                [power setShowsMenuAsPrimaryAction:YES];

                [power addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
                    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
                    [gen impactOccurred];
                }] forControlEvents:UIControlEventPrimaryActionTriggered];
            }

            [view addSubview:power];
        }

        NSDictionary *addColorDict = [[NSUserDefaults standardUserDefaults] objectForKey:@"addButtonColorDict" inDomain:domain];
        UIColor *addColor = addColorDict ? [UIColor colorWithRed:[addColorDict[@"red"] floatValue] green:[addColorDict[@"green"] floatValue] blue:[addColorDict[@"blue"] floatValue] alpha:1.0] : [UIColor whiteColor];
        plus.tintColor = addColor;

        NSDictionary *powerColorDict = [[NSUserDefaults standardUserDefaults] objectForKey:@"powerButtonColorDict" inDomain:domain];
        UIColor *powerColor = powerColorDict ? [UIColor colorWithRed:[powerColorDict[@"red"] floatValue] green:[powerColorDict[@"green"] floatValue] blue:[powerColorDict[@"blue"] floatValue] alpha:1.0] : [UIColor whiteColor];
        power.tintColor = powerColor;

        // Update Frames (z. B. bei Rotation)
        plus.frame = CGRectMake(safeLeft - 10, yOffset - 10, buttonSize + 15, buttonSize + 15);
        power.frame = CGRectMake(view.bounds.size.width - safeRight - buttonSize - 10, yOffset - 10, buttonSize + 15, buttonSize + 15);

        // Animation je nach Zustand
        switch (state) {
            case 1: {
                plus.transform = CGAffineTransformMakeScale(0.6, 0.6);
                power.transform = CGAffineTransformMakeScale(0.6, 0.6);
                [UIView animateWithDuration:0.45
                                    delay:0.0
                    usingSpringWithDamping:0.7
                    initialSpringVelocity:0.5
                                    options:UIViewAnimationOptionCurveEaseOut
                                animations:^{
                    plus.alpha = 1.0;
                    plus.transform = CGAffineTransformIdentity;
                    power.alpha = 1.0;
                    power.transform = CGAffineTransformIdentity;
                } completion:nil];
                break;
            }
            case 3: {
                [UIView animateWithDuration:0.2 animations:^{
                    plus.alpha = 0.0;
                    plus.transform = CGAffineTransformMakeScale(0.6, 0.6);
                    power.alpha = 0.0;
                    power.transform = CGAffineTransformMakeScale(0.6, 0.6);
                }];
                break;
            }
            default:
                break;
        }
    }
}
%end

%end // CC26 group

static void loadPreferences(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSNumber *enabledValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"enabled" inDomain:domain];
    enabled = (enabledValue) ? [enabledValue boolValue] : NO;
    NSNumber *enableTopButtonsValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"enableTopButtons" inDomain:domain];
    enableTopButtons = (enableTopButtonsValue) ? [enableTopButtonsValue boolValue] : YES;
    NSNumber *colorSliderGlyphsValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"colorSliderGlyphs" inDomain:domain];
    colorSliderGlyphs = (colorSliderGlyphsValue) ? [colorSliderGlyphsValue boolValue] : YES;
    NSNumber *showBordersValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"showBorders" inDomain:appearanceDomain];
    showBorders = showBordersValue ? [showBordersValue boolValue] : NO;
    NSNumber *lightnessValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"ios18Lightness" inDomain:appearanceDomain];
    ios18Lightness = lightnessValue ? [lightnessValue boolValue] : YES;
    NSNumber *roundnessValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"cornerRoundness" inDomain:appearanceDomain];
    cornerRoundness = roundnessValue ? MIN(1.5, MAX(0.5, [roundnessValue floatValue])) : 1.0;

    // Media player position overrides (-1 = default)
    NSNumber *val;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaArtworkX" inDomain:domain];
    mediaArtworkX = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaArtworkY" inDomain:domain];
    mediaArtworkY = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaArtworkSize" inDomain:domain];
    mediaArtworkSize = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaRoutingBtnX" inDomain:domain];
    mediaRoutingBtnX = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaRoutingBtnY" inDomain:domain];
    mediaRoutingBtnY = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaRoutingBtnSize" inDomain:domain];
    mediaRoutingBtnSize = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaLabelX" inDomain:domain];
    mediaLabelX = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaLabelY" inDomain:domain];
    mediaLabelY = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaLabelW" inDomain:domain];
    mediaLabelW = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaLabelH" inDomain:domain];
    mediaLabelH = val ? [val floatValue] : -1;
    val = [[NSUserDefaults standardUserDefaults] objectForKey:@"mediaLabelLineSpacing" inDomain:domain];
    mediaLabelLineSpacing = val ? [val floatValue] : 1.0;
}

%ctor {
    loadPreferences(NULL, NULL, NULL, NULL, NULL); // Load prefs
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, loadPreferences, (CFStringRef)preferencesNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, loadPreferences, (CFStringRef)appearanceNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
    if (enabled) {
        %init(CC26)
    }
}