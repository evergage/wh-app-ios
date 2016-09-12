/*
 * This project constitutes a work of the United States Government and is
 * not subject to domestic copyright protection under 17 USC § 105.
 *
 * However, because the project utilizes code licensed from contributors
 * and other third parties, it therefore is licensed under the MIT
 * License.  http://opensource.org/licenses/mit-license.php.  Under that
 * license, permission is granted free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the conditions that any appropriate copyright notices and this
 * permission notice are included in all copies or substantial portions
 * of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
//
//  AppDelegate.m
//  WhiteHouse
//


#import "AppDelegate.h"
#import "SWRevealViewController.h"
#import "LiveViewController.h"
#import "MainViewController.h"
#import "SidebarViewController.h"
#import "AFHTTPRequestOperation.h"
#import "WHFeedItem.h"
#import "FavoritesViewController.h"
#import "DOMParser.h"
#import <Evergage/Evergage.h>


@interface AppDelegate ()<SWRevealViewControllerDelegate>

@end

@implementation AppDelegate

#define USE_STAGING_FEEDS (false)

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    //Evergage Integration
    Evergage *evergage = [Evergage sharedInstance];
    NSString *evgAccountKey = @"demo";
    NSString *evgDatasetId = @"whitehouse";
    
#ifdef DEBUG
    // Development settings
    evergage.logLevel = EVGLogLevelWarn;
    [evergage allowDesignConnections];
#endif
    [evergage startWithEvergageAccountKey:evgAccountKey dataset:evgDatasetId];
    
    
    // Override point for customization after application launch.
    
    _placeholderImages = [[NSMutableArray alloc] init];
    
    
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    UIColor *blue = [UIColor colorWithRed:0.0 green:0.2 blue:0.4 alpha:1.0];
    [[UINavigationBar appearance] setBarTintColor:blue];
    [[UINavigationBar appearance]setTitleTextAttributes:@{NSForegroundColorAttributeName : [UIColor whiteColor]}];
    [[UINavigationBar appearance] setTintColor:[UIColor whiteColor]];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont
                                                                           fontWithName:@"Times" size:20], NSFontAttributeName,
                                [UIColor whiteColor], NSForegroundColorAttributeName, nil];
    
    [[UINavigationBar appearance] setTitleTextAttributes:attributes];
    
    if ([UIApplication instancesRespondToSelector:@selector(registerUserNotificationSettings:)]) {
        [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound
                                                                                                              categories:nil]];
    }
    
    // set badge icon to 0
    application.applicationIconBadgeNumber = 0;
    
    [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    
    [self setupNavigation];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDirectory = [paths objectAtIndex:0];
    NSString *dataFilePath = [docDirectory stringByAppendingPathComponent:@"livedata"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:dataFilePath]) {
        NSArray *dictsFromFile = [[NSMutableArray alloc] initWithContentsOfFile:dataFilePath];
        _livePosts = dictsFromFile;
        DOMParser * parser = [[DOMParser alloc] init];
        _liveEventCount = [parser upcomingPostCount:dictsFromFile];
    }
    
    return YES;
}

-(BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    if ([[Evergage sharedInstance] handleOpenURL:url]) {
        return YES;
    }
    return NO;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
    [_blogData removeAllObjects];
    [_videoData removeAllObjects];
    [_briefingRoomData removeAllObjects];
}

# pragma BackgroundFetch

-(void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler{
    NSDate *fetchStart = [NSDate date];
    
    LiveViewController *liveViewController = [[LiveViewController alloc]init];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDirectory = [paths objectAtIndex:0];
    NSString *menuPath = [docDirectory stringByAppendingPathComponent:@"menuData"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:menuPath]) {
        _menuItems = [[NSMutableArray alloc] initWithContentsOfFile:menuPath];
        _liveFeed = [[_menuItems objectAtIndex:4] objectForKey:@"feed-url"];
    }else{
        _liveFeed = @"http://www.whitehouse.gov/feed/mobile/live";
    }

    [liveViewController fetchNewDataWithCompletionHandler:^(UIBackgroundFetchResult result) {
        completionHandler(result);
        
        NSDate *fetchEnd = [NSDate date];
        NSTimeInterval timeElapsed = [fetchEnd timeIntervalSinceDate:fetchStart];
        NSLog(@"Background Fetch Duration: %f seconds", timeElapsed);
    }];
}

# pragma notifications

- (void)application:(UIApplication *)app didReceiveLocalNotification:(UILocalNotification *)localNotification{
    if (localNotification) {
        _liveLink = [localNotification.userInfo valueForKey:@"url"];
    }
    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    if (state == UIApplicationStateActive) {
        NSDate *eventStart = localNotification.fireDate;
        NSDate *eventBefore = [eventStart dateByAddingTimeInterval:(-31*60)];
        NSDate* sourceDate = [NSDate date];
        NSTimeZone* sourceTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        NSTimeZone* destinationTimeZone = [NSTimeZone systemTimeZone];
        NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
        NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
        NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
        NSDate *timeNow = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
        
        if([Post date:timeNow isBetweenDate:eventBefore andDate:eventStart]){
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"In 30 Minutes"
                                                            message:localNotification.alertBody
                                                           delegate:self cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
        }
    }
}

- (void) setupNavigation{
    // Updating menu from whitehouse JSON
    
    NSString *menuUrl = [NSString stringWithFormat:@"http://www.whitehouse.gov/sites/default/files/feeds/config.json"];
    NSURL *url = [NSURL URLWithString:menuUrl];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDirectory = [paths objectAtIndex:0];
    NSString *menuPath = [docDirectory stringByAppendingPathComponent:@"menuData"];
    
    // todo: entry to enable/disable recs/smart-search?
    NSArray *menuItemsToAdd = @[
                                @{@"title" : @"Favorites"},
                                @{@"title" : @"Recommendations"}
                                ];
    
    if USE_STAGING_FEEDS {
        NSString *file = [[NSBundle mainBundle] pathForResource:@"feeds" ofType:@"json"];
        NSString *str = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
        NSError *jsonError;
        NSData *objectData = [str dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:objectData
                                                             options:NSJSONReadingMutableContainers
                                                               error:&jsonError];
        _menuJSON = json[@"feeds"];
        [_menuJSON writeToFile:menuPath atomically: YES];
        _menuItems = [[NSMutableArray alloc] initWithArray: _menuJSON];
        [self preloadData];
        
    }else{
        AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
        operation.responseSerializer = [AFJSONResponseSerializer serializer];
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObject:@"text/plain"];
        [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            
            _menuJSON = responseObject[@"feeds"];
            if (![_menuJSON writeToFile:menuPath atomically:YES]) {
                NSLog(@"Couldn't save menu config");
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:menuPath]) {
                _menuItems = [[NSMutableArray alloc] initWithContentsOfFile:menuPath];
                [_menuItems addObjectsFromArray:menuItemsToAdd];
            }
            //        [_searchTableView reloadData];    uncommment to force relad of menu config
            
            [self preloadData];
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:menuPath]) {
                _menuItems = [[NSMutableArray alloc] initWithContentsOfFile:menuPath];
                [_menuItems addObjectsFromArray:menuItemsToAdd];
            }
            NSLog(@"Error fetching menu config");
        }];
        [operation start];
    }

    
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:menuPath]) {
        _menuItems = [[NSMutableArray alloc] initWithContentsOfFile:menuPath];
        [_menuItems addObjectsFromArray:menuItemsToAdd];
        _activeFeed = [[_menuItems objectAtIndex:0] objectForKey:@"feed-url"];
        _liveFeed = [[_menuItems objectAtIndex:4] objectForKey:@"feed-url"];
    }else{
        _activeFeed = @"http://www.whitehouse.gov/feed/mobile/blog";
        _liveFeed = @"http://www.whitehouse.gov/feed/mobile/live";
    }
    LiveViewController *liveViewController = [[LiveViewController alloc]init];
    [liveViewController fetchLiveData];
}

-(void)preloadData{
    DOMParser * parser = [[DOMParser alloc] init];
    NSURL *briefingUrl = [[NSURL alloc] initWithString:[[_menuItems objectAtIndex:1] objectForKey:@"feed-url"]];
    parser.xml = [NSString stringWithContentsOfURL:briefingUrl encoding:NSUTF8StringEncoding error:nil];
    _briefingRoomData = [[NSMutableArray alloc]init];
    [_briefingRoomData addObjectsFromArray:[parser parseFeed]];
    NSURL *photoUrl = [[NSURL alloc] initWithString:[[_menuItems objectAtIndex:2] objectForKey:@"feed-url"]];
    parser.xml = [NSString stringWithContentsOfURL:photoUrl encoding:NSUTF8StringEncoding error:nil];
    _photoData = [[NSMutableArray alloc]init];
    [_photoData addObjectsFromArray:[parser parseFeed]];
    NSURL *videoUrl = [[NSURL alloc] initWithString:[[_menuItems objectAtIndex:3] objectForKey:@"feed-url"]];
    parser.xml = [NSString stringWithContentsOfURL:videoUrl encoding:NSUTF8StringEncoding error:nil];
    _videoData = [[NSMutableArray alloc]init];
    [_videoData addObjectsFromArray:[parser parseFeed]];
    // Wow, app is making synchronous network calls.  Anyhow, currently recs is on-demand in the VC and not pre-loaded or saved beyond VC instance
}

@end
