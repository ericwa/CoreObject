/*
    Copyright (C) 2013 Eric Wasylishen, Quentin Mathe

    Date:  August 2013
    License:  MIT  (see COPYING)
 */

#import "TestCommon.h"

@interface COUndoTrackStore (TestUndoTrackStore)
- (BOOL)commitTransaction;
@end

@interface TestUndoTrackStore : NSObject <UKTest>
{
    COUndoTrackStore *_store;
}

@end


@implementation TestUndoTrackStore

- (instancetype)init
{
    SUPERINIT;

    _store = [[COUndoTrackStore alloc] initWithURL: [SQLiteStoreTestCase undoTrackStoreURL]];
    [_store clearStore];
    [_store beginTransaction];
    [_store removeTrackWithName: @"test1"];
    [_store removeTrackWithName: @"test2"];
    [_store commitTransaction];

    return self;
}

- (void)testNoTrackNames
{
    NSArray *names = _store.trackNames;
    UKFalse([names containsObject: @"test1"]);
    UKFalse([names containsObject: @"test2"]);
}

- (COUndoTrackSerializedCommand *)makeCommandWithParent: (ETUUID *)aParent track: (NSString *)aTrack
{
    COUndoTrackSerializedCommand *cmd = [COUndoTrackSerializedCommand new];
    cmd.JSONData = @{@"a": @"b"};
    cmd.metadata = @{@"c": @"d"};
    cmd.UUID = [ETUUID UUID];
    cmd.parentUUID = aParent;
    cmd.trackName = aTrack;
    cmd.timestamp = [NSDate date];
    return cmd;
}

- (void)checkCommand: (COUndoTrackSerializedCommand *)actual
    isEqualToCommand: (COUndoTrackSerializedCommand *)expected
{
    UKObjectsEqual(expected.UUID, actual.UUID);
    UKObjectsEqual(expected.JSONData, actual.JSONData);
    if (expected.parentUUID == nil)
    {
        UKNil(actual.parentUUID);
    }
    else
    {
        UKObjectsEqual(expected.parentUUID, actual.parentUUID);
    }
    UKObjectsEqual(expected.trackName, actual.trackName);
    UKObjectsEqual(CODateFromJavaTimestamp(CODateToJavaTimestamp(expected.timestamp)),
                   actual.timestamp);
    UKIntsEqual(expected.sequenceNumber, actual.sequenceNumber);
    UKObjectsEqual(expected.metadata, actual.metadata);
}

- (void)checkState: (COUndoTrackState *)actual isEqualToState: (COUndoTrackState *)expected
{
    UKObjectsEqual(expected.trackName, actual.trackName);
    UKObjectsEqual(expected.headCommandUUID, actual.headCommandUUID);
    if (expected.currentCommandUUID == nil)
    {
        UKNil(actual.currentCommandUUID);
    }
    else
    {
        UKObjectsEqual(expected.currentCommandUUID, actual.currentCommandUUID);
    }
}

- (void)testBasic
{
    COUndoTrackSerializedCommand *cmd1 = [self makeCommandWithParent: nil track: @"test1"];
    COUndoTrackSerializedCommand *cmd2 = [self makeCommandWithParent: cmd1.UUID track: @"test1"];

    COUndoTrackState *state = [COUndoTrackState new];
    state.trackName = @"test1";
    state.headCommandUUID = cmd2.UUID;
    state.currentCommandUUID = cmd1.UUID;

    [_store beginTransaction];
    [_store addCommand: cmd1];
    [_store addCommand: cmd2];
    [_store setTrackState: state];
    [_store commitTransaction];

    UKTrue([[_store trackNames] containsObject: @"test1"]);

    // Try reloading

    COUndoTrackState *reloadedState = [_store stateForTrackName: @"test1"];
    [self checkState: reloadedState isEqualToState: state];

    COUndoTrackSerializedCommand *reloadedCmd1 = [_store commandForUUID: cmd1.UUID];
    [self checkCommand: reloadedCmd1 isEqualToCommand: cmd1];

    COUndoTrackSerializedCommand *reloadedCmd2 = [_store commandForUUID: cmd2.UUID];
    [self checkCommand: reloadedCmd2 isEqualToCommand: cmd2];

    // Commit a new command.

    COUndoTrackSerializedCommand *cmd3 = [self makeCommandWithParent: cmd1.UUID track: @"test1"];

    COUndoTrackState *state2 = [COUndoTrackState new];
    state2.trackName = @"test1";
    state2.headCommandUUID = cmd3.UUID;
    state2.currentCommandUUID = cmd3.UUID;

    [_store beginTransaction];
    [_store addCommand: cmd3];
    [_store setTrackState: state2];
    [_store commitTransaction];

    // Try reloading

    COUndoTrackState *reloadedState2 = [_store stateForTrackName: @"test1"];
    [self checkState: reloadedState2 isEqualToState: state2];

    COUndoTrackSerializedCommand *reloadedCmd3 = [_store commandForUUID: cmd3.UUID];
    [self checkCommand: reloadedCmd3 isEqualToCommand: cmd3];
}

/**
 * NULL is a special value for current command UUID that means "the start of the track"
 */
- (void)testNullCurrentCommandPermitted
{
    COUndoTrackSerializedCommand *cmd1 = [self makeCommandWithParent: nil track: @"test1"];

    COUndoTrackState *state = [COUndoTrackState new];
    state.trackName = @"test1";
    state.headCommandUUID = cmd1.UUID;
    state.currentCommandUUID = cmd1.UUID;

    [_store beginTransaction];
    [_store addCommand: cmd1];
    [_store setTrackState: state];
    [_store commitTransaction];

    state.currentCommandUUID = nil;

    [_store beginTransaction];
    [_store setTrackState: state];
    [_store commitTransaction];

    // Try reloading

    COUndoTrackState *reloadedState2 = [_store stateForTrackName: @"test1"];
    [self checkState: reloadedState2 isEqualToState: state];
}

- (void)testDivergent
{
    COUndoTrackSerializedCommand *cmd1 = [self makeCommandWithParent: nil track: @"test1"];
    COUndoTrackSerializedCommand *cmd1a = [self makeCommandWithParent: cmd1.UUID track: @"test1"];
    COUndoTrackSerializedCommand *cmd1b = [self makeCommandWithParent: cmd1.UUID track: @"test1"];

    COUndoTrackState *state = [COUndoTrackState new];
    state.trackName = @"test1";
    state.headCommandUUID = cmd1b.UUID;
    state.currentCommandUUID = cmd1b.UUID;

    [_store beginTransaction];
    [_store addCommand: cmd1];
    [_store addCommand: cmd1a];
    [_store addCommand: cmd1b];
    [_store setTrackState: state];
    [_store commitTransaction];

    UKObjectsEqual(S(cmd1.UUID, cmd1a.UUID, cmd1b.UUID),
                   SA([_store allCommandUUIDsOnTrackWithName: @"test1"]));
}

@end


@implementation COUndoTrackStore (TestUndoTrackStore)

- (BOOL)commitTransaction
{
    return [self commitTransactionWithCompletionHandler: ^() { }];
}

@end

