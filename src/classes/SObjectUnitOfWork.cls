/**
 * @author FinancialForce.com, Inc. with modifications by Kevin Rice
 * @date 2012, modifications 2017.06
 * @group Data Access Layer
 * @description Used in modified form in compliance with terms of use. See end of source code for conditions, disclaimers, and notices. 
 **/

public class SObjectUnitOfWork {
	
    private List<Schema.SObjectType> m_sObjectTypes = new List<Schema.SObjectType>();
	private Map<String, List<SObject>> m_newListByType = new Map<String, List<SObject>>();
	private Map<String, List<SObject>> m_dirtyListByType = new Map<String, List<SObject>>();
	private Map<String, List<SObject>> m_deletedListByType = new Map<String, List<SObject>>();
	private Map<String, Relationships> m_relationships = new Map<String, Relationships>();
    
    /** @description Utilized by commitWorkAllowPartial method in case any record insert/updates fail **/
    private Map<SObject,String> m_failed = new Map<SObject,String>();  
    private Boolean hasInserts = false; 
    private Boolean hasUpdates = false; 
    private Boolean hasDeletes = false; 

	/**
	 * @description Constructs a new UnitOfWork to support work against the given object list
	 * @param *sObjectTypes* A list of Schema.SObjectTypes given in dependency order (least dependent first)
	 */
	public SObjectUnitOfWork(List<Schema.SObjectType> sObjectTypes) {
        m_sObjectTypes = sObjectTypes.clone();
			
		for(Schema.SObjectType sObjectType : m_sObjectTypes)
		{
			m_newListByType.put(sObjectType.getDescribe().getName(), new List<SObject>());
			m_dirtyListByType.put(sObjectType.getDescribe().getName(), new List<SObject>());
			m_deletedListByType.put(sObjectType.getDescribe().getName(), new List<SObject>());
			m_relationships.put(sObjectType.getDescribe().getName(), new Relationships());	
		}
	}
    
    /** @description Returns the Map of SObject types to their list of records for insertion **/
    public Map<String, List<SObject>> getNewListByType() { return this.m_newListByType; }
    
    /** @description Returns the Map of SObject types to their list of records for update **/
    public Map<String, List<SObject>> getDirtyListByType() { return this.m_dirtyListByType; }
    
    /** @description Returns the Map of SObject types to their list of records for deletion **/
    public Map<String, List<SObject>> getDeletedListByType() { return this.m_deletedListByType; }
    
    /**
     * @description Allows the caller to verify if there is work to be committed or not. Useful when units of work are passed amongst multiple methods. 
     * @return (Boolean) True if there are records to insert, update or delete in the current instance. 
     **/
    public Boolean hasWorkToCommit() { 
        
        // if any lists have records, return true
        for (List<SObject> inserts : m_newListByType.values())
            if (inserts.size() > 0) return true; 
        for (List<SObject> updates : m_dirtyListByType.values())
            if (updates.size() > 0) return true; 
        for (List<SObject> deletes : m_deletedListByType.values())
            if (deletes.size() > 0) return true; 
        
        return false; 
    }
	
	/**
	 * @description Register a newly created SObject instance to be inserted 
	 * @param *record* A newly created SObject instance to be inserted during commitWork
	 **/
	public void registerNew(SObject record) { registerNew(record, null, null); }

	/**
	 * @description Register a newly created SObject instance to be inserted; you may also provide a reference to the parent record instance (should also be registered as new separately)
	 * @param *record* A newly created SObject instance to be inserted during commitWork
	 * @param *relatedToParentField* A SObjectField reference to the child field that associates the child record with its parent
	 * @param *relatedToParentRecord* A SObject instance of the parent record (should also be registered as new separately)
	 **/
	public void registerNew(SObject record, Schema.sObjectField relatedToParentField, SObject relatedToParentRecord) {
		if(record.Id != null)
			throw new UnitOfWorkException('Only new records can be registered as new');
        
		String sObjectType = record.getSObjectType().getDescribe().getName();			
		if(!m_newListByType.containsKey(sObjectType))
			throw new UnitOfWorkException(String.format('SObject type {0} is not supported by this unit of work', new String[] { sObjectType }));
        
        // add record and set hasInserts, if first call to this method
		m_newListByType.get(sObjectType).add(record);
        if (!hasInserts) {
            hasInserts = true; 
        }
        
		if(relatedToParentRecord!=null && relatedToParentField!=null)
			registerRelationship(record, relatedToParentField, relatedToParentRecord);
	}
	
	/**
	 * @description Register a relationship between two records where (at least) the relatedTo SObject has yet to be inserted to the database. This information will be used during the commitWork phase to make the references only when related records have been inserted to the database.
	 * @param *record* An existing or newly created record. If existing, the SObject record must also be passed to RegisterDirty. 
	 * @param *relatedToField* A SObjectField referene to the lookup field that relates the two records together
	 * @param *relatedTo* A SOBject instance (yet to be commited to the database)
	 */
	public void registerRelationship(SObject record, Schema.sObjectField relatedToField, SObject relatedTo) {
		String sObjectType = record.getSObjectType().getDescribe().getName();		
		if(!m_newListByType.containsKey(sObjectType))
			throw new UnitOfWorkException(String.format('SObject type {0} is not supported by this unit of work', new String[] { sObjectType }));
        
		m_relationships.get(sObjectType).add(record, relatedToField, relatedTo);
	}
	
	/**
	 * @description Register an existing record to be updated during the commitWork method
	 * @param *record* An existing record
	 **/
	public void registerDirty(SObject record) {
		if(record.Id == null)
			throw new UnitOfWorkException('New records cannot be registered as dirty');
        
		String sObjectType = record.getSObjectType().getDescribe().getName();			
		if(!m_dirtyListByType.containsKey(sObjectType))
			throw new UnitOfWorkException(String.format('SObject type {0} is not supported by this unit of work', new String[] { sObjectType }));
        
        // add record and set hasUpdates, if false
		m_dirtyListByType.get(sObjectType).add(record);		
        if (!hasUpdates) {
            hasUpdates = true; 
        }
	}
	
	/**
	 * @description Register an existing record to be deleted during the commitWork method
	 * @param *record* An existing record
	 **/
	public void registerDeleted(SObject record) {
		if(record.Id == null)
			throw new UnitOfWorkException('New records cannot be registered for deletion');
        
		String sObjectType = record.getSObjectType().getDescribe().getName();			
		if(!m_deletedListByType.containsKey(sObjectType))
			throw new UnitOfWorkException(String.format('SObject type {0} is not supported by this unit of work', new String[] { sObjectType }));
        
        // add record, and set hasDeletes, if false
		m_deletedListByType.get(sObjectType).add(record);							
        if (!hasDeletes) {
            hasDeletes = true; 
        }
	}
	
	/**
	 * @description Takes all the work that has been registered with the UnitOfWork and commits it to the database
	 **/
	public void commitWork() {
        
		// Wrap the work in its own transaction 
		Savepoint sp = Database.setSavePoint();		
		try {	
            
            // Insert by type
            if (hasInserts) {
                system.debug('SObjectUnitOfWork attempting to INSERT records (all-or-none processing)');
                for(Schema.SObjectType sObjectType : m_sObjectTypes) {
                    m_relationships.get(sObjectType.getDescribe().getName()).resolve(); 
                    insert m_newListByType.get(sObjectType.getDescribe().getName()); 
                }   
            }
            
            // Update by type
            if (hasUpdates) {
                system.debug('SObjectUnitOfWork attempting to UPDATE records (all-or-none processing)');
                for(Schema.SObjectType sObjectType : m_sObjectTypes) {
                    update m_dirtyListByType.get(sObjectType.getDescribe().getName());
                }   
            }
            
            // Delete by type (in reverse dependency order)
            if (hasDeletes) {
                Integer objectIdx = m_sObjectTypes.size() - 1;
                while(objectIdx>=0) {
                    String objName = m_sObjectTypes[objectIdx--].getDescribe().getName();
                    List<SObject> deletions = m_deletedListByType.get(objName); 
                    if (deletions.size() > 0) {
                        system.debug('SObjectUnitOfWork attempting to DELETE ' + objName + ' records, enforcing all-or-none processing...');
                        delete deletions;
                    }
                }    
            }
            
        } catch (Exception e) {
            // Rollback
            Database.rollback(sp);
            // Throw exception on to caller
            system.debug('Exception occurred during SObjectUnitOfWork.commitWork. All DML operations have been rolled back.');
            system.debug('Message: ' + e.getMessage()); 
            system.debug('Stack Trace: ' + e.getStackTraceString());
            throw e;
        }
	}
    
    /**
     * @description Custom addition to financial-force implementation. Allows DML operations to complete with partial success, with exception of delete operations, which always operate
     * in an all-or-none fashion. When this method is used, the failure of a single update or insert operation will not result in the rollback of the entire transaction. Unhandled non-DML exceptions
     * will still result in a rollback, however. This method should be used with caution, as unexpected results may occur when there are relationships between SObjects being inserted and/or updated. 
     * @return Map<SObject,String>. Map of SObject records that failed along with their concatenated failure logs. Map will return empty if no records failed. 
     **/
    public Map<SObject,String> commitWorkAllowPartialSuccess() {

        // Set savepoint in case of need to rollback transaction
		Savepoint sp = Database.setSavePoint();	
        
        try {
            
            /******** INSERT by type ********/
            if (hasInserts) {
                system.debug('SObjectUnitOfWork attempting to INSERT records (allowing partial success)');
                for(Schema.SObjectType sObjectType : m_sObjectTypes) {
                    String objName = sObjectType.getDescribe().getName();
                    List<SObject> inserts = m_newListByType.get(objName);

                    // use the resolveAllowPartial method, which returns a list of SObjects whose relatedTo could not be resolved to an id (e.g. parent record failed insert in prior iteration)
                    List<SObject> dependentFails = m_relationships.get(objName).resolveAllowPartial();
                    if (dependentFails.size() > 0) {
                        for (SObject dep : dependentFails) {
                            for (Integer i = inserts.size() - 1; i >= 0; i--) {
                                SObject ins = inserts.get(i); 
                                if (dep == ins) {
                                    String err = '\n' + objName + ' is dependent on a related SObject which failed insert in a previous iteration.\n'; 
                                    system.debug(err); 
                                    m_failed.put(dep,err); 
                                    inserts.remove(i); 
                                    break; 
                                }
                            }
                        }
                    }
                    
                    // perform DML insert, allowing partial success
                    Database.SaveResult[] dsr = Database.insert(inserts,false); 
                    Integer i = 0; 
                    for (Database.SaveResult result : dsr) {
                        if (!result.isSuccess()) { 
                            SObject failObject = inserts.get(i); 
                            String failString = '\n SObjectUnitOfWork errored while attempting to insert ' + objName + ': '; 
                            String failConcat = ''; 
                            for (Database.Error err : result.getErrors()) {
                                String a = 'Message: ' + err.getMessage() + ' || ' + 'Status Code: ' + err.getStatusCode() + '|| ' + 'Fields: ' + err.getFields() + '\n'; 
                                failConcat += a; 
                            }
                            String err = failString + failConcat;
                            system.debug(err); 
                            m_failed.put(failObject,err);
                        }
                        i++; 
                    }
                }
            }

            /******** UPDATE by type ********/
            if (hasUpdates) {
                system.debug('SObjectUnitOfWork attempting to UPDATE records (allowing partial success)');
                for(Schema.SObjectType sObjectType : m_sObjectTypes) {
                    
                    String objName = sObjectType.getDescribe().getName(); 
                    List<SObject> updates = m_dirtyListByType.get(objName);
                    
                    // use the resolveAllowPartial method, which returns a list of SObjects whose relatedTo could not be resolved to an id (e.g. parent record failed insert in prior iteration)
                    List<SObject> dependentFails = m_relationships.get(objName).resolveAllowPartial();
                    if (dependentFails.size() > 0) {
                        for (SObject dep : dependentFails) {
                            for (Integer i = updates.size() - 1; i >= 0; i--) {
                                SObject ins = updates.get(i); 
                                if (dep == ins) {
                                    String err = '\n' + objName + ' is dependent on a related SObject which failed insert in a previous iteration.\n';
                                    system.debug(err); 
                                    m_failed.put(dep,err); 
                                    updates.remove(i); 
                                    break; 
                                }
                            }
                        }
                    } 
                    
                    // perform DML update, allowing partial success
                    Database.SaveResult[] dsr = Database.update(updates,false);
                    Integer i = 0; 
                    for (Database.SaveResult result : dsr) {
                        if (!result.isSuccess()) {
                            SObject failObject = updates.get(i); 
                            String failString = '\n SObjectUnitOfWork errored while attempting to update ' + objName + ': '; 
                            String failConcat = ''; 
                            for (Database.Error err : result.getErrors()) {
                                String a = 'Message: ' + err.getMessage() + ' || ' + 'Status Code: ' + err.getStatusCode() + ' || ' + 'Fields: ' + err.getFields() + '\n'; 
                                failConcat += a; 
                            }
                            String err = failString + failConcat;
                            system.debug(err); 
                            m_failed.put(failObject,err);
                        }
                        i++; 
                    }
                }
            }

            if (hasDeletes) {
                /******** DELETE by type (in reverse dependency order) ********/
                Integer objectIdx = m_sObjectTypes.size() - 1;
                while(objectIdx>=0) {
                    String objName = m_sObjectTypes[objectIdx--].getDescribe().getName();
                    List<SObject> deletions = m_deletedListByType.get(objName); 
                    if (deletions.size() > 0) {
                        system.debug('SObjectUnitOfWork attempting to DELETE ' + objName + ' records, enforcing all-or-none processing...');
                        delete deletions;
                    }
                }    
            }
            
        } catch (Exception e) {
            // Rollback
			Database.rollback(sp);
			// Throw exception on to caller
			system.debug('Exception occurred during SObjectUnitOfWork.commitWorkAllowPartial.');
            system.debug('Message: ' + e.getMessage()); 
            system.debug('Stack Trace: ' + e.getStackTraceString()); 
			throw e;
        }

        return m_failed; 
        
    }
	
	private class Relationships {
        
		private List<Relationship> m_relationships = new List<Relationship>();

        public void resolve() {
			// Resolve relationships
			for(Relationship relationship : m_relationships)
				relationship.Record.put(relationship.RelatedToField, relationship.RelatedTo.Id);
		}
        
        public List<SObject> resolveAllowPartial() {
            
            List<SObject> dependentFails = new List<SObject>(); 
            
            for (Relationship relationship : m_relationships) {
                
                Id relatedId = relationship.RelatedTo.Id;
                
                // if the relatedId is null, it means the related record failed insert in a previous step; add it to the list of SObjects for removal and continue
                if (relatedId == null) {
                    dependentFails.add(relationship.Record);
                    continue; 
                } 
                
                // ensure related Id is not null, and is not already equal to the relatedId
                if ( (relatedId != null) && (relationship.Record.get(relationship.RelatedToField.getDescribe().getName()) != relatedId) ) {
                    try {
                        relationship.Record.put(relationship.RelatedToField, relatedId);
                    } catch (Exception e) {
                        system.debug('SObjectUnitOfWork.Relationships.resolveAllowPartial() unhandled exception: ' + e.getMessage());
                        system.debug('Error resolving relatedId for Relationship ' + relationship); 
                        throw e; 
                    }
                }
            }
            
            return dependentFails; 
        }
		
        public void add(SObject record, Schema.sObjectField relatedToField, SObject relatedTo) {
			// Relationship to resolve
			Relationship relationship = new Relationship();
			relationship.Record = record;
			relationship.RelatedToField = relatedToField;
			relationship.RelatedTo = relatedTo;
			m_relationships.add(relationship);
		}
        
	}
	
	private class Relationship {
		public SObject Record;
		public Schema.sObjectField RelatedToField;
		public SObject RelatedTo; 
	}
	
	/**
	 * @description UnitOfWork Exception
	 **/
	public class UnitOfWorkException extends Exception {}
}
    
/**
 * Copyright (c) 2012, FinancialForce.com, inc
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice, 
 *      this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *      this list of conditions and the following disclaimer in the documentation 
 *      and/or other materials provided with the distribution.
 * - Neither the name of the FinancialForce.com, inc nor the names of its contributors 
 *      may be used to endorse or promote products derived from this software without 
 *      specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

/**
 * Provides an implementation of the Enterprise Application Architecture Unit Of Work, as defined by Martin Fowler
 *   http://martinfowler.com/eaaCatalog/unitOfWork.html
 *
 * "When you're pulling data in and out of a database, it's important to keep track of what you've changed; otherwise, 
 *  that data won't be written back into the database. Similarly you have to insert new objects you create and 
 *  remove any objects you delete."
 *
 * "You can change the database with each change to your object model, but this can lead to lots of very small database calls, 
 *  which ends up being very slow. Furthermore it requires you to have a transaction open for the whole interaction, which is 
 *  impractical if you have a business transaction that spans multiple requests. The situation is even worse if you need to
 *  keep track of the objects you've read so you can avoid inconsistent reads."
 *
 * "A Unit of Work keeps track of everything you do during a business transaction that can affect the database. When you're done, 
 *  it figures out everything that needs to be done to alter the database as a result of your work."
 *
 * In an Apex context this pattern provides the following specific benifits
 *  - Applies bulkfication to DML operations, insert, update and delete
 *  - Manages a business transaction around the work and ensures a rollback occurs (even when exceptions are later handled by the caller)
 *  - Honours dependency rules between records and updates dependent relationships automatically during the commit 
 *
 * Please refer to the testMethod's in this class for example usage 
 *
 * TODO: Need to complete the 100% coverage by covering parameter exceptions in tests
 * TODO: Need to add some more test methods for more complex use cases and some unexpected (e.g. registerDirty and then registerDeleted)
 *
 **/