#import "HumbugAppDelegate.h"
#import "KeychainItemWrapper.h"
#import "NSString+Encode.h"
#import "HumbugAPIClient.h"
#import "ZulipAPIController.h"

// AFNetworking
#import "AFNetworkActivityIndicatorManager.h"
#import "AFJSONRequestOperation.h"

// Crashlytics
#import <Crashlytics/Crashlytics.h>

@implementation HumbugAppDelegate

@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.errorViewController = [[ErrorViewController alloc] init];

    KeychainItemWrapper *keychainItem = [[KeychainItemWrapper alloc]
                                         initWithIdentifier:@"HumbugLogin" accessGroup:nil];
    NSString *storedApiKey = [keychainItem objectForKey:(__bridge id)kSecValueData];
    NSString *storedEmail = [keychainItem objectForKey:(__bridge id)kSecAttrAccount];

    if ([storedApiKey isEqual: @""]) {
        // No credentials stored; we need to log in.
        self.loginViewController = [[LoginViewController alloc] init];
        [self.navController pushViewController:self.loginViewController animated:YES];
    } else {
        // We have credentials, so try to reuse them. We may still have to log in if they are stale.
        self.apiKey = storedApiKey;
        self.email = storedEmail;

        [HumbugAPIClient setCredentials:self.email withAPIKey:self.apiKey];
    }
    
    self.streamViewController = [[StreamViewController alloc] init];
    // Bottom padding so you can see new messages arrive.
    self.streamViewController.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, 200.0, 0.0);
    self.navController = [[UINavigationController alloc] initWithRootViewController:self.streamViewController];
    [[self window] setRootViewController:self.navController];

    // Connect the API controller to the home view, and connect to the Zulip API
    [[ZulipAPIController sharedInstance] setHomeViewController:self.streamViewController];
    [[ZulipAPIController sharedInstance] registerForQueue];

    // Set out NSURLCache settings
    NSURLCache *URLCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
    [NSURLCache setSharedURLCache:URLCache];

    self.clientID = @"";

    [self.window makeKeyAndVisible];

    [Crashlytics startWithAPIKey:@"7c523eb4efdbd264d6d4a7403ee7a683b733a9bd"];
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    /*
     Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
     Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
     */
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    /*
     Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
     If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
     */
    self.streamViewController.timeWhenBackgrounded = [[NSDate date] timeIntervalSince1970];
    self.streamViewController.backgrounded = TRUE;
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    /*
     Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
     */
    [self.streamViewController reset];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    /*
     Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
     */
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    /*
     Called when the application is about to terminate.
     Save data if appropriate.
     See also applicationDidEnterBackground:.
     */
}

- (void) login:(NSString *)username password:(NSString *)password result:(void (^) (bool success))result;
{
    NSMutableDictionary *postFields = [NSMutableDictionary dictionaryWithObjectsAndKeys:username, @"username",
                                       password, @"password", nil];
    
    [[HumbugAPIClient sharedClient] postPath:@"fetch_api_key" parameters:postFields success:^(AFHTTPRequestOperation *operation , id responseObject) {
        NSDictionary *jsonDict = (NSDictionary *)responseObject;

        self.apiKey = [jsonDict objectForKey:@"api_key"];
        self.email = username;

        [HumbugAPIClient setCredentials:self.email withAPIKey:self.apiKey];

        KeychainItemWrapper *keychainItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"HumbugLogin" accessGroup:nil];
        [keychainItem setObject:self.apiKey forKey:(__bridge id)kSecValueData];
        [keychainItem setObject:self.email forKey:(__bridge id)kSecAttrAccount];

        result(YES);
    } failure: ^( AFHTTPRequestOperation *operation , NSError *error ){
        NSLog(@"Failed to fetch_api_key %@", [error localizedDescription]);

        result(NO);
    }];
}

- (void)viewStream
{
    [self.navController popViewControllerAnimated:YES];
}

- (void)showErrorScreen:(UIView *)view errorMessage:(NSString *)errorMessage
{
    [self.window addSubview:self.errorViewController.view];
    self.errorViewController.whereWeCameFrom = view;
    self.errorViewController.errorMessage.text = errorMessage;
}

- (void)dismissErrorScreen
{
    [self.errorViewController.view removeFromSuperview];
}


#pragma mark - Core Data

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext {
    if (__managedObjectContext != nil) {
        return __managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        __managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [__managedObjectContext setPersistentStoreCoordinator:coordinator];
    }

    return __managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel != nil) {
        return __managedObjectModel;
    }
    __managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];

    return __managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (__persistentStoreCoordinator != nil) {
        return __persistentStoreCoordinator;
    }

    __persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];

//    AFIncrementalStore *incrementalStore = (AFIncrementalStore *)[__persistentStoreCoordinator addPersistentStoreWithType:[ZulipIncrementalStore type] configuration:nil URL:nil options:nil error:nil];

    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"Zulip.sqlite"];

    NSDictionary *options = @{
                              NSInferMappingModelAutomaticallyOption : @(YES),
                              NSMigratePersistentStoresAutomaticallyOption: @(YES)
                              };

    NSError *error = nil;
    [__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error];
    if (error) {
        NSLog(@"Error initializing persistent sqlite store! %@, %@", [error localizedDescription], [error userInfo]);
        abort();
    }
    
    NSLog(@"SQLite URL: %@", storeURL);

    return __persistentStoreCoordinator;
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

@end
