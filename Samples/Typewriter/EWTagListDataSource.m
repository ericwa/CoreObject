/*
	Copyright (C) 2014 Eric Wasylishen
 
	Date:  February 2014
	License:  MIT  (see COPYING)
 */

#import "EWTagListDataSource.h"
#import "EWTypewriterWindowController.h"

@implementation EWTagListDataSource

@synthesize owner, outlineView;

- (id) init
{
	SUPERINIT;
	oldSelection = [NSMutableSet new];
	return self;
}

- (id) rootObject
{
	return rootTreeNode;
}

- (id) outlineView: (NSOutlineView *)outlineView child: (NSInteger)index ofItem: (id)item
{
	if (nil == item) { item = [self rootObject]; }
	NSTreeNode *treeNode = item;
	
	return [[treeNode childNodes] objectAtIndex: index];
}

- (BOOL) outlineView: (NSOutlineView *)ov isItemExpandable: (id)item
{
	return [self outlineView: ov numberOfChildrenOfItem: item] > 0;
}

- (NSInteger) outlineView: (NSOutlineView *)outlineView numberOfChildrenOfItem: (id)item
{
	if (nil == item) { item = [self rootObject]; }
	NSTreeNode *treeNode = item;
	
	return [[treeNode childNodes] count];
}

- (id) outlineView: (NSOutlineView *)outlineView objectValueForTableColumn: (NSTableColumn *)column byItem: (id)item
{
	if (nil == item) { item = [self rootObject]; }
	NSTreeNode *treeNode = item;
		
	return [(COObject *)[treeNode representedObject] name];
}

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if (nil == item) { item = [self rootObject]; }
	NSTreeNode *treeNode = item;
	
	COObject *treeNodeRepObj = [treeNode representedObject];
	
	NSString *oldName = [treeNodeRepObj name] != nil ? [treeNodeRepObj name] : @"";
	NSString *newName = [object stringValue] != nil ? [object stringValue] : @"";
	
	[(COObject *)treeNodeRepObj setName: object];
	
	if ([treeNodeRepObj isTag])
	{
		[self.owner commitWithIdentifier: @"rename-tag" descriptionArguments: @[oldName, newName]];
	}
	else
	{
		[self.owner commitWithIdentifier: @"rename-tag-group" descriptionArguments: @[oldName, newName]];
	}
}

- (void)cacheSelection
{
	if ([[self.outlineView selectedRowIndexes] count] != 0)
	{
		[oldSelection removeAllObjects];
		NSIndexSet *indexes = [self.outlineView selectedRowIndexes];
		for (NSUInteger i = [indexes firstIndex]; i != NSNotFound; i = [indexes indexGreaterThanIndex: i])
		{
			COObject *object = [[self.outlineView itemAtRow: i] representedObject];
			[oldSelection addObject: object.UUID];
		}
		NSLog(@"Caching selected tags as %@", oldSelection);
		if ([oldSelection isEmpty])
		{
			NSLog(@"hih");
		}
	}
}

- (void) setNextSelection: (ETUUID *)aUUID
{
	nextSelection = aUUID;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	[self cacheSelection];
	[self.owner selectTag: nil];
}

- (void)reloadData
{
	// Build tree nodes
	
	COTagLibrary *library = [self.owner tagLibrary];
	rootTreeNode = [[NSTreeNode alloc] initWithRepresentedObject: library];
	for (COTagGroup *tagGroup in [library tagGroups])
	{
		NSTreeNode *tagGroupNode = [[NSTreeNode alloc] initWithRepresentedObject: tagGroup];
		[[rootTreeNode mutableChildNodes] addObject: tagGroupNode];
		for (COTag *tag in [tagGroup content])
		{
			NSTreeNode *tagNode = [[NSTreeNode alloc] initWithRepresentedObject: tag];
			[[tagGroupNode mutableChildNodes] addObject: tagNode];			
		}
	}
	
	[self.outlineView reloadData];
	[self.outlineView expandItem: nil expandChildren: YES]; // Initially expand all tags - needs to be done before the selection restoration
	
	NSSet *uuidsToSelect;
	if (nextSelection != nil)
	{
		uuidsToSelect = S(nextSelection);
	}
	else
	{
		uuidsToSelect = oldSelection;
	}
	nextSelection = nil;
	
	NSMutableIndexSet *newSelectedRows = [NSMutableIndexSet new];
	for (ETUUID *uuid in uuidsToSelect)
	{
		for (NSInteger row = 0; row < [self.outlineView numberOfRows]; row++)
		{
			if ([[[[self.outlineView itemAtRow: row] representedObject] UUID] isEqual: uuid])
			{
				[newSelectedRows addIndex: row];
				break;
			}
		}
	}
	[self.outlineView selectRowIndexes: newSelectedRows byExtendingSelection: NO];
	[self cacheSelection];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	return [[item representedObject] isKindOfClass: [COTagGroup class]];
}

#pragma mark Drag & Drop

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
	if ([[[info draggingPasteboard] types] containsObject: EWTagDragType])
	{
		if ([[item representedObject] isKindOfClass: [COTagGroup class]])
			return NSDragOperationMove;
	}
	else if ([[[info draggingPasteboard] types] containsObject: EWNoteDragType])
	{
		if ([[item representedObject] isTag])
			return NSDragOperationMove;
	}
	return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
	NSPasteboard *pasteboard = [info draggingPasteboard];
	
	if ([[[info draggingPasteboard] types] containsObject: EWTagDragType])
	{
		COTagGroup *tagGroup = [item representedObject];
		ETAssert([tagGroup isKindOfClass: [COTagGroup class]]);
		
		id plist = [pasteboard propertyListForType: EWTagDragType];
		COTag *tag = [[[self.owner tagLibrary] objectGraphContext] loadedObjectForUUID: [ETUUID UUIDWithString: plist]];
		ETAssert(tag != nil);
		
		[tagGroup addObject: tag];
		
		[self.owner commitWithIdentifier: @"move-tag" descriptionArguments: @[tag.name != nil ? tag.name : @""]];
	}
	else if ([[[info draggingPasteboard] types] containsObject: EWNoteDragType])
	{
		COTag *tag = [item representedObject];
		ETAssert([tag isTag]);
		
		for (NSPasteboardItem *pbItem in [pasteboard pasteboardItems])
		{
			id plist = [pbItem propertyListForType: EWNoteDragType];
			COPersistentRoot *notePersistentRoot = [owner.editingContext persistentRootForUUID: [ETUUID UUIDWithString: plist]];
			ETAssert(notePersistentRoot != nil);
			
			COObject *noteRootObject = [notePersistentRoot rootObject];
			
			[tag addObject: noteRootObject];
		}
		
		[self.owner commitWithIdentifier: @"tag-note" descriptionArguments: @[tag.name != nil ? tag.name : @""]];
	}
	
	return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pb
{
	if ([items count] != 1)
		return NO;
	
	if (![[items[0] representedObject] isTag])
		return NO;
	
	NSMutableArray *pbItems = [NSMutableArray array];
    
	for (NSTreeNode *node in items)
	{
		COObject *item = [node representedObject];
		NSPasteboardItem *pbitem = [[NSPasteboardItem alloc] init];
		[pbitem setPropertyList: [[item UUID] stringValue] forType: EWTagDragType];
		[pbItems addObject: pbitem];
	}
	
	[pb clearContents];
	return [pb writeObjects: pbItems];
}

@end
