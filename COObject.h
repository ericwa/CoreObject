/*
	Copyright (C) 2010 Eric Wasylishen

	Author:  Eric Wasylishen <ewasylishen@gmail.com>, 
	         Quentin Mathe <quentin.mathe@gmail.com>
	Date:  November 2010
	License:  Modified BSD  (see COPYING)
 */

#import <Foundation/Foundation.h>
#import <EtoileFoundation/EtoileFoundation.h>
#import <ObjectMerging/COQuery.h>

@class COEditingContext, CORevision, COCommitTrack;

/**
 * Working copy of an object, owned by an editing context.
 * Relies on the context to resolve fault references to other COObjects.
 *
 * You should use ETUUID's to refer to objects outside of the context
 * of a COEditingContext.
 */
@interface COObject : NSObject <NSCopying, COObjectMatching>
{
	@package
	ETEntityDescription *_entityDescription;
	ETUUID *_uuid;
	COEditingContext *_context; // weak reference
	COObject *_rootObject; // weak reference
	NSMapTable *_variableStorage;
	BOOL _isIgnoringDamageNotifications;
	BOOL _isIgnoringRelationshipConsistency;
	BOOL _inDescription; // FIXME: remove; only for debugging
}

/** @taskunit Initialization */

/** <init />
 * Initializes and returns a non-persistent object.
 *
 * The receiver can be made persistent later, by inserting it into an editing 
 * context with -becomePersistentInContext:rootObject:.<br />
 * Its identity will remain stable once persistency has been enabled, because 
 * this initializer gives a UUID to the object.
 *
 * You should use insertion methods provided by COEditingContext to create 
 * objects that are immediately persistent.
 */
- (id)init;

/** 
 * Makes the receiver persistent by inserting it into the given editing context.
 *
 * If the root object argument is the receiver itself, then the receiver becomes 
 * a root object (or a persistent root from the storage standpoint).
 *
 * Raises an exception if any argument is nil.<br />
 * When the root object is not the receiver or doesn't belong to the editing 
 * context, raises an exception too.
 */
- (void)becomePersistentInContext: (COEditingContext *)aContext 
                       rootObject: (COObject *)aRootObject;
- (id)copyWithZone: (NSZone *)aZone usesModelDescription: (BOOL)usesModelDescription;

/** taskunit Persistency Attributes */

/** 
 * Returns the UUID that uniquely identifies the persistent object that 
 * corresponds to the receiver.
 *
 * A persistent object has a single instance per editing context.
 */
- (ETUUID *)UUID;
- (ETEntityDescription *)entityDescription;
/** 
 * Returns the editing context when the receiver is persistent, otherwise  
 * returns nil.
 */
- (COEditingContext *)editingContext;
/** 
 * Returns the root object when the receiver is persistent, otherwise returns nil.
 *
 * When the receiver is persistent, returns either self or the root object that 
 * encloses the receiver as an embedded object.
 *
 * See also -isRoot.
 */
- (COObject *)rootObject;
- (BOOL)isFault;
/**
 * Returns whether the receiver is saved on the disk.
 *
 * When persistent, the receiver has both a valid editing context and root object.
 */
- (BOOL)isPersistent;
/** 
 * Returns whether the receiver is a root object that can enclose embedded 
 * objects.
 *
 * Embedded or non-persistent objects returns NO.
 *
 * See also -rootObject.
 */
- (BOOL)isRoot;
- (BOOL)isDamaged;

/** @taskunit History Attributes */

/**
 * Return the revision of this object in the editing context.
 */
- (CORevision *)revision;
/**
 * Returns the commit track for this object.
 */
- (COCommitTrack *)commitTrack;

/** @taskunit Contained Objects based on the Metamodel */

/**
 * Returns an array containing all COObjects "strongly contained" by this one.
 * This means objects which are values for "composite" properties.
 */
- (NSArray *)allStronglyContainedObjects;
- (NSArray *)allStronglyContainedObjectsIncludingSelf;

/** @taskunit Basic Properties */

/**
 * The object name.
 */
@property (nonatomic, retain) NSString *name;

/**
 * Returns -name.
 */
- (NSString *)displayName;

/** @taskunit Property-Value Coding */

- (NSArray *)propertyNames;
- (NSArray *)persistentPropertyNames;
- (id)valueForProperty:(NSString *)key;
- (BOOL)setValue:(id)value forProperty:(NSString*)key;

/** @taskunit Direct Access to the Variable Storage */

/**
 * Returns a value from the variable storage.
 *
 * Can be used to read a property with no instance variable.
 *
 * This is a low-level method whose use should be restricted to serialization 
 * code and accessors that expose properties with no related instance variable.
 */
- (id)primitiveValueForKey: (NSString *)key;
/**
 * Sets a value in the variable storage.
 *
 * Can be used to write a property with no instance variable.
 *
 * This is a low-level method whose use should be restricted to serialization 
 * code and accessors that expose properties with no related instance variable.
 *
 * This methods involves no integrity check or relationship consistency update.
 * It won't invoke -willChangeValueForProperty: and -didChangeValueForProperty: 
 * (or -willChangeValueForKey: and -didChangeValueForKey:).
 */
- (void)setPrimitiveValue: (id)value forKey: (NSString *)key;

/** @taskunit Collection Mutation with Integrity Check */

- (void)addObject: (id)object forProperty:(NSString *)key;
- (void)insertObject: (id)object atIndex: (NSUInteger)index forProperty:(NSString *)key;
- (void)removeObject: (id)object forProperty:(NSString *)key;
- (void)removeObject: (id)object atIndex: (NSUInteger)index forProperty:(NSString *)key;

/** @taskunit Notifications to be called by Accessors */

/**
 * Tells the receiver that the value of the property (transient or persistent) 
 * is about to change.
 *
 * By default, limited to calling -willChangeValueForKey:.
 *
 * Can be overriden, but the superclass implementation must be called.
 */
- (void)willChangeValueForProperty: (NSString *)key;
/**
 * Tells the receiver that the value of the property (transient or persistent)
 * has changed. 
 *
 * By default, notifies the editing context about the receiver change and 
 * triggers Key-Value-Observing notifications by calling -didChangeValueForKey:.
 *
 * Can be overriden, but the superclass implementation must be called.
 */
- (void)didChangeValueForProperty: (NSString *)key;

/** @taskunit Overridable Notifications */

/**
  * A notification that the object was created for the first time.
  * Override this method to perform any initialisation that should be
  * performed the very first time an object is instantiated, such
  * as calculating and setting default values.
  */
- (void)didCreate;
- (void)awakeFromInsert;
- (void)awakeFromFetch;
- (void)willTurnIntoFault;
- (void)didTurnIntoFault;

/** @taskunit Overriden NSObject methods */

- (NSString *)description;
- (BOOL)isEqual: (id)otherObject;

/** @taskunit Object Matching */

/**
 * Returns the receiver put in an array when it matches the query, otherwise 
 * returns an empty array.
 */
- (NSArray *)objectsMatchingQuery: (COQuery *)aQuery;

@end


@interface COObject (Private)

/** 
 * Returns COObjectFault. 
 */
+ (Class) faultClass;
- (NSError *) unfaultIfNeeded;
- (void) notifyContextOfDamageIfNeededForProperty: (NSString*)prop;
- (void) turnIntoFault;

- (BOOL) isIgnoringRelationshipConsistency;
- (void) setIgnoringRelationshipConsistency: (BOOL)ignore;
- (void)updateRelationshipConsistencyWithValue: (id)value forKey: (NSString *)key;
@end


@interface COObject (PropertyListImportExport)

- (id)serializedValueForProperty:(NSString *)key;
- (BOOL)setSerializedValue:(id)value forProperty:(NSString*)key;
- (NSDictionary*) propertyListForValue: (id)value;
- (NSDictionary*) referencePropertyList;
- (NSObject *)valueForPropertyList: (NSObject*)plist;

@end


@interface COObject (PrivateToEditingContext)

/**
 * If isFault is NO, the object is initialized as a newly inserted object.
 */
- (id) initWithUUID: (ETUUID*)aUUID 
  entityDescription: (ETEntityDescription*)anEntityDescription
         rootObject: (id)aRootObject
            context: (COEditingContext*)aContext
            isFault: (BOOL)isFault;
/**
 * Used only by -[COEditingContext markObject[Un]damaged]; to update
 * the object's cached damage flag
 */
// - (void) setDamaged: (BOOL)isDamaged;

@end

/*
// FIXME: these are a bit of a mess
@interface COObject (PropertyListImportExport)

- (NSDictionary*) propertyList;
- (NSDictionary*) referencePropertyList;

- (void)unfaultWithData: (NSDictionary*)data;

@end
*/

@interface COObject (Debug)
- (id) roundTripValueForProperty: (NSString *)key;
- (NSString*)detailedDescription;
@end
