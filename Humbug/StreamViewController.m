#import "FirstViewController.h"
#import "HumbugAppDelegate.h"
#import "HumbugAPIClient.h"
#import "ComposeViewController.h"
#import "UIColor+HexColor.h"
#include "ZulipAPIController.h"
#include "ZFetchRequest.h"

#import "ZMessage.h"
#import "ZUser.h"

#import "AFJSONRequestOperation.h"

@interface StreamViewController () <NSFetchedResultsControllerDelegate> {
    NSFetchedResultsController *_fetchedResultsController;
}

@property (assign) BOOL initialLoad;

- (void)refetchData;

@end

@implementation StreamViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    id ret = [super initWithStyle:style];
    _fetchedResultsController = 0;
    self.initialLoad = YES;

    return ret;
}

- (void)refetchData {
    // Refetches all our messages
    [_fetchedResultsController performSelectorOnMainThread:@selector(performFetch:) withObject:nil waitUntilDone:YES modes:@[ NSRunLoopCommonModes ]];
}

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setTitle:@"Zulip"];
    
    self.backgrounded = FALSE;
    self.waitingOnErrorRecovery = FALSE;
    self.delegate = (HumbugAppDelegate *)[UIApplication sharedApplication].delegate;
    
    UIImage *composeButtonImage = [UIImage imageNamed:@"glyphicons_355_bullhorn.png"];
    UIButton *composeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [composeButton setImage:composeButtonImage forState:UIControlStateNormal];
    composeButton.frame = CGRectMake(0.0, 0.0, composeButtonImage.size.width + 40,
                                     composeButtonImage.size.height);
    [composeButton addTarget:self action:@selector(composeButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *uiBarComposeButton = [[UIBarButtonItem alloc] initWithCustomView:composeButton];
    [[self navigationItem] setRightBarButtonItem:uiBarComposeButton];
    
    UIImage *composePMButtonImage = [UIImage imageNamed:@"glyphicons_003_user.png"];
    UIButton *composePMButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [composePMButton setImage:composePMButtonImage forState:UIControlStateNormal];
    composePMButton.frame = CGRectMake(0.0, 0.0, composeButtonImage.size.width + 40,
                                       composeButtonImage.size.height);
    [composePMButton addTarget:self action:@selector(composePMButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *uiBarComposePMButton = [[UIBarButtonItem alloc] initWithCustomView:composePMButton];
    [[self navigationItem] setLeftBarButtonItem:uiBarComposePMButton];
}

- (void)viewDidAppear:(BOOL)animated
{
    // This function gets called whenever the stream view appears, including returning to the view after popping another view. We only want to backfill old messages on the very first load.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];

    // Release any cached data, images, etc. that aren't in use.
}

- (void)viewDidUnload
{
    [super viewDidUnload];

    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [[_fetchedResultsController sections] count];
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[[_fetchedResultsController sections] objectAtIndex:section] numberOfObjects];
}

+ (UIColor *)defaultStreamColor {
    return [UIColor colorWithRed:187.0/255
                           green:187.0/255
                            blue:187.0/255
                           alpha:1];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [(MessageCell *)cell willBeDisplayed];
}

- (ZMessage *)messageAtIndexPath:(NSIndexPath *)indexPath
{
    @try {
        return (ZMessage *)[_fetchedResultsController objectAtIndexPath:indexPath];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
        return nil;
    }
}

-(UITableViewCell *)tableView:(UITableView *)tableView
        cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ZMessage *message = [self messageAtIndexPath:indexPath];
    
    MessageCell *cell = (MessageCell *)[self.tableView dequeueReusableCellWithIdentifier:
                                        [MessageCell reuseIdentifier]];
    if (cell == nil) {
        [[NSBundle mainBundle] loadNibNamed:@"MessageCellView" owner:self options:nil];
        cell = self.messageCell;
        self.messageCell = nil;
    }

    [cell setMessage:message];

    return cell;
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZMessage * message = [self messageAtIndexPath:indexPath];
    return [MessageCell heightForCellWithMessage:message];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    ComposeViewController *composeView = [[ComposeViewController alloc]
                                          initWithNibName:@"ComposeViewController"
                                          bundle:nil];

    ZMessage *message = [self messageAtIndexPath:indexPath];
    composeView.type = message.type;
    [[self navigationController] pushViewController:composeView animated:YES];

    if ([message.type isEqualToString:@"stream"]) {
        composeView.recipient.text = message.stream_recipient;
        [composeView.subject setHidden:NO];
        composeView.subject.text = message.subject;
    } else if ([message.type isEqualToString:@"private"]) {
        [composeView.subject setHidden:YES];

        NSSet *recipients = message.pm_recipients;
        NSMutableArray *recipient_array = [[NSMutableArray alloc] init];
        for (ZUser *recipient in recipients) {
            if (![recipient.email isEqualToString:self.delegate.email]) {
                [recipient_array addObject:recipient.email];
            }
        }
        composeView.privateRecipient.text = [recipient_array componentsJoinedByString:@", "];
    }
}

#pragma mark - StreamViewController

- (void)loadSubscriptionData:(NSArray *)subscriptions
{
    NSMutableDictionary *streamdict = [[NSMutableDictionary alloc] init];
    for (NSDictionary* stream in subscriptions) {
        [streamdict setObject:stream forKey:[stream objectForKey:@"name"]];
    }
    [self setStreams:streamdict];
}

- (void)initialPopulate
{
    if (_fetchedResultsController) {
        _fetchedResultsController = 0;
    }

    // This is the home view, so we want to display all messages
    ZFetchRequest *fetchRequest = [ZFetchRequest fetchRequestWithEntityName:@"ZMessage"];
    fetchRequest.sortDescriptors = [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"messageID" ascending:NO]];
    fetchRequest.fetchOffset = 0; // 0 offset + descending means starting from the end
    fetchRequest.fetchBatchSize = 5;
    [fetchRequest setIncludesSubentities:YES];
    // API requests need the pointer for the anchor
    fetchRequest.anchor = [[ZulipAPIController sharedInstance] pointer];
    // Zulip addition because we want results in reverse order
    fetchRequest.reverseResults = YES;

    _fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                                                    managedObjectContext:[self.delegate managedObjectContext]
                                                                      sectionNameKeyPath:nil
                                                                               cacheName:@"AllMessages"];
    _fetchedResultsController.delegate = self;
    // Load initial set of messages
    NSLog(@"Initially populating!");
    [self refetchData];
    [self.tableView reloadData];
}

- (BOOL) streamInHome:(NSString *)stream
{
    NSDictionary *streamInfo = [[self streams] objectForKey:stream];

    if (!streamInfo) {
        return YES;
    }

    return [[streamInfo objectForKey:@"in_home_view"] boolValue];
}

- (void) updatePointer {
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self performSelectorInBackground:@selector(updatePointer) withObject: nil];
}

-(void)composeButtonPressed {
    ComposeViewController *composeView = [[ComposeViewController alloc]
                                    initWithNibName:@"ComposeViewController"
                                    bundle:nil];
    composeView.type = @"stream";
    [[self navigationController] pushViewController:composeView animated:YES];
}

-(void)composePMButtonPressed {
    ComposeViewController *composeView = [[ComposeViewController alloc]
                                     initWithNibName:@"ComposeViewController"
                                     bundle:nil];
    composeView.type = @"private";
    [[self navigationController] pushViewController:composeView animated:YES];
}

-(int) rowWithId: (int)messageId
{
    int i = 0;
    for (i = 0; i < [[[_fetchedResultsController sections] objectAtIndex:0] numberOfObjects]; i++) {
        ZMessage *message = [self messageAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
        if ([message.messageID intValue] == messageId) {
            return i;
        }
    }
    return FALSE;
}

-(void)repopulateList
{
    [[[HumbugAPIClient sharedClient] operationQueue] cancelAllOperations];
    [self initialPopulate];
    [self.tableView reloadData];
}

-(void)scrollToPointer:(long)newPointer animated:(BOOL)animated
{
    int pointerRowNum = [self rowWithId:newPointer];
    if (pointerRowNum) {
        NSLog(@"Scrolling to pointer");
        // If the pointer is already in our table, but not visible, scroll to it
        // but don't try to clear and refetch messages.
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath
                                                indexPathForRow:pointerRowNum
                                                inSection:0]
                              atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:animated];
    }
    [[ZulipAPIController sharedInstance] setPointer:newPointer];
}

-(void)reset {
    // Hide any error screens if visible
    [self.delegate dismissErrorScreen];

    // Fetch the pointer, then reset
    [[HumbugAPIClient sharedClient] getPath:@"users/me" parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSDictionary *json = (NSDictionary *)responseObject;
        int updatedPointer = [[json objectForKey:@"pointer"] intValue];

        if (updatedPointer != -1) {
            [self scrollToPointer:updatedPointer animated:NO];
            self.backgrounded = FALSE;
        }

        [self repopulateList];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failed to fetch pointer: %@", [error localizedDescription]);
        [self repopulateList];
    }];
}

- (UIColor *)streamColor:(NSString *)withName {
    NSDictionary *stream = [[self streams] objectForKey:withName];
    if (stream == NULL) {
        NSLog(@"Error loading stream data to fetch color, %@", withName);
        return [StreamViewController defaultStreamColor];
    }
    NSString* colorHex = [stream objectForKey:@"color"];
    if (colorHex == NULL || [colorHex isEqualToString:@""]) {
        NSLog(@"Got no color for stream %@", withName);
        return [StreamViewController defaultStreamColor];
    }

    return [UIColor colorWithHexString:colorHex defaultColor:[StreamViewController defaultStreamColor]];
}

#pragma mark - NSFetchedResultsControllerDelegate methods
/*
 Assume self has a property 'tableView' -- as is the case for an instance of a UITableViewController
 subclass -- and a method configureCell:atIndexPath: which updates the contents of a given cell
 with information from a managed object at the given index path in the fetched results controller.
 */

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView beginUpdates];
}


- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type
{
    NSLog(@"Section change!");
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex]
                          withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex]
                          withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}


- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {

    UITableView *tableView = self.tableView;

    switch(type) {

        case NSFetchedResultsChangeInsert:
//            NSLog(@"Added object: %@", newIndexPath);
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeDelete:
//            NSLog(@"Removed object: %@", newIndexPath);

            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeUpdate:
        {
//            NSLog(@"Changed object: %i", [newIndexPath row]);
            MessageCell *cell = (MessageCell *)[self.tableView cellForRowAtIndexPath:newIndexPath];
            ZMessage *message = [self messageAtIndexPath:newIndexPath];

            [cell setMessage:message];
            break;
        }
        case NSFetchedResultsChangeMove:
//            NSLog(@"Moved object: from %i to %i", [indexPath row], [newIndexPath row]);

            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView endUpdates];
//    NSLog(@"FInished changing content");
    if (self.initialLoad) {
        self.initialLoad = NO;
        NSLog(@"Done with initial load, scrolling to pointer");
        [self scrollToPointer:[[ZulipAPIController sharedInstance] pointer] animated:NO];
    }
}

@end
