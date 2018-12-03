/**
 * @author FinancialForce.com, Inc. with modifications by Kevin Rice
 * @description Used in modified form in compliance with terms of use. See end of source code for conditions, disclaimers, and notices. Serves as the base class
 * for all extending Domain classes. Note that extending classes must also have an inner class, named "Constructor", that implements the SObjectDomain.IConstructable interface
 * in order for Apex Triggers of that object to delegate to the domain class. 
 **/

public abstract class SObjectDomain {
    
    /** @description Records is the List<SObject> that will be operated on by the extending Domain class. **/
    public List<SObject> Records { get; private set;}
	/** @description SObjectDescribe is the Schema.DescribeSObjectResult of the SObject types in Records. **/
    public Schema.DescribeSObjectResult SObjectDescribe { get; private set; } 
    /** @description Name of the SObject **/
    public String sObjectName { get; private set; }
    /** @description Boolean that determines if object-level-security is enforced **/
    public Boolean isOLSEnforced { get; private set; }
    /** @description String that represents the concrete implementation of a given SObjectDomain instance **/
    public System.Type domainType { get; private set; }
    
	/**
	 * @description Default constructor.
	 * @param *sObjectList* List<SObject>. List of records to which domain logic will be applied.
	 **/
    public SObjectDomain(List<SObject> SObjects) {
		this(SObjects, true); 
	}
    
    /**
     * @description Constructor which allows bypass of object-level-security
     * @param *sObjectList* List<SObject>. List of records to which domain logic will be applied.
     * @param *isOLSEnforced* Boolean. When set to true, object-level-security for the user in context will be enforced. Default is true. 
     **/ 
    public SObjectDomain(List<SObject> SObjects, Boolean isOLSEnforced) {
        this.Records = SObjects;
		this.SObjectDescribe = Records.getSObjectType().getDescribe();
        this.sObjectName = SObjectDescribe.getName(); 
        this.isOLSEnforced = isOLSEnforced; 
        // set domain name of concrete instance
        String concrete; 
        try {
            concrete = String.valueOf(this).split(':')[0]; 
        } catch (Exception e) {
            concrete = 'SObjectDomain'; 
        }
        this.domainType = System.Type.forName(concrete); 
    }
    
    /**************************** Protected Virtual Methods ****************************/
	
	/** @description Override this to apply defaults to the records, this is called by the handleBeforeInsert method. **/
	protected virtual void doApplyDefaults() { }
	
	/** @description Override this to apply general validation to be performed during insert or update, called by the handleAfterInsert and handleAfterUpdate methods. **/
	protected virtual void doValidate() { }
	
	/** @description Override this to apply validation to be performed during insert, called by the handleAfterUpdate method. **/
	protected virtual void doValidate(Map<Id,SObject> existingRecords)	{ }

	/** @description Override this to perform processing during the before insert phase, this is called by the handleBeforeInsert method. **/
    protected virtual void doBeforeInsert() { }
    
	/** @description Override this to perform processing during the before update phase, this is called by the handleBeforeUpdate method. **/
    protected virtual void doBeforeUpdate(Map<Id,SObject> existingRecords) { }
    
	/** @description Override this to perform processing during the before delete phase, this is called by the handleBeforeDelete method. **/
    protected virtual void doBeforeDelete() { }
    
    /** @description Override this to perform processing during the before undelete phase, this is called by the handleBeforeUndelete method. **/
    protected virtual void doBeforeUndelete() { }
    
	/** @description Override this to perform processing during the after insert phase, this is called by the handleAfterInsert method. **/
    protected virtual void doAfterInsert() { }
    
	/** @description Override this to perform processing during the after update phase, this is called by the handleAfterUpdate method. **/    
    protected virtual void doAfterUpdate(Map<Id,SObject> existingRecords) { }
    
	/** @description Override this to perform processing during the after delete phase, this is called by the handleAfterDelete method. **/    
    protected virtual void doAfterDelete() { }	
    
    /** @description Override this to perform processing during the after undelete phase, this is called by the handleAfterUndelete method. **/
    protected virtual void doAfterUndelete(Map<Id,SObject> newMap) { }
	
    
    /**************************** Private Methods ****************************/
    
	/** @description Base handler for the Apex Trigger event Before Insert, calls the doApplyDefaults method, followed by doBeforeInsert. **/
    private void handleBeforeInsert() {
    	doApplyDefaults(); 
    	doBeforeInsert();
    }
    
    /** @description Base handler for the Apex Trigger event Before Update, calls the doBeforeUpdate method. **/
    private void handleBeforeUpdate(Map<Id,SObject> existingRecords) {
        doBeforeUpdate(existingRecords);
    }
    
    /** @description Base handler for the Apex Trigger event Before Delete, calls the doBeforeDelete method. **/
    private void handleBeforeDelete() {
    	doBeforeDelete();
    }
    
    /** @description Base handler for the Apex Trigger event Before Undelete, calls the doBeforeUndelete method. **/
    private void handleBeforeUndelete() {
        doBeforeUndelete(); 
    }
    
    /** @description Base handler for the Apex Trigger event After Insert, checks object security and calls the doValidate and doAfterInsert methods. Throws exception if the current user context is not able to create records. */
    private void handleAfterInsert() {
        if(this.isOLSEnforced && !SObjectDescribe.isCreateable()) {
            
        }
        
    	doValidate();
    	doAfterInsert(); 
    }
    
    /** @description Base handler for the Apex Trigger event After Update, checks object security and calls the doValidate, doValidate(Map<Id,SObject>) and doAfterUpdate methods. Throws exception if the current user context is not able to update records. **/
    private void handleAfterUpdate(Map<Id,SObject> existingRecords) {
        if(this.isOLSEnforced && !SObjectDescribe.isUpdateable()) {

        }
        
    	doValidate();
    	doValidate(existingRecords);
    	doAfterUpdate(existingRecords); 
    }
    
    /** @description Base handler for the Apex Trigger event After Delete, checks object security and calls the doAfterDelete method. Throws exception if the current user context is not able to delete records. **/
    private void handleAfterDelete() {
        if(this.isOLSEnforced && !SObjectDescribe.isDeletable()) {

        }
        
    	doAfterDelete();
    }	
    
    /** @description Base handler for the Apex Trigger event After Undelete, calls the doAfterUndelete method. **/
    private void handleAfterUndelete(Map<Id,SObject> newMap) {
        doAfterUndelete(newMap); 
    }
	
    /** @description Inner interface that subclasses of SObjectDomain must also implement, in an inner class named "Constructor", such that triggerHandler() can dynamically instantiate them **/
    public interface IConstructable {
		SObjectDomain construct(List<SObject> sObjectList);
	}
    
    /**************************** Static Methods - called by SObject Triggers ****************************/
	
	/** @description Constructs the given Domain class with the current Trigger context before calling the applicable override methods such as beforeInsert, beforeUpdate etc. **/
    public static void triggerHandler(Type domainClass) {
		
        // Construct the domain class constructor class
		String domainClassName = domainClass.getName();
        system.debug('**** BEGIN SObjectDomain.TriggerHandler(). Constructing domainClass of type ' + domainClassName + ' ****');
		Type constructableClass = domainClassName.endsWith('Constructor') ? Type.forName(domainClassName) : Type.forName(domainClassName+'.Constructor');
        if (constructableClass == null) {

        }
        
		IConstructable constructor = (IConstructable) constructableClass.newInstance();
		
        // Process the trigger context
        if (System.Test.isRunningTest()) {
            // FinancialForce comment: If in test context, and records in the mock database, delegate initially to the mock database trigger handler
            // TODO test logic code
        } else {
            // Process the runtime Apex Trigger context 
            triggerHandler(constructor, 
                           Trigger.isBefore, 
                           Trigger.isAfter, 
                           Trigger.isInsert, 
                           Trigger.isUpdate, 
                           Trigger.isDelete,
                           Trigger.isUndelete,
                           Trigger.new, 
                           Trigger.oldMap,
                           Trigger.newMap);
        }
	}
	
	/** @description Calls the applicable override methods such as beforeInsert, beforeUpdate etc. based on a Trigger context. **/
    private static void triggerHandler(IConstructable domainConstructor, 
                                       Boolean isBefore, Boolean isAfter, Boolean isInsert, Boolean isUpdate, Boolean isDelete, Boolean isUndelete, 
                                       List<SObject> newRecords, Map<Id, SObject> oldRecordsMap, Map<Id, SObject> newRecordsMap) {
        if (isBefore) {
	        if (isInsert) domainConstructor.construct(newRecords).handleBeforeInsert();
	        else if (isUpdate) domainConstructor.construct(newRecords).handleBeforeUpdate(oldRecordsMap);
	        else if (isDelete) domainConstructor.construct(oldRecordsMap.values()).handleBeforeDelete();
            else if (isUndelete) domainConstructor.construct(newRecords).handleBeforeUndelete(); 
	    } else {
	        if (isInsert) domainConstructor.construct(newRecords).handleAfterInsert();
	        else if (isUpdate) domainConstructor.construct(newRecords).handleAfterUpdate(oldRecordsMap);
	        else if (isDelete) domainConstructor.construct(oldRecordsMap.values()).handleAfterDelete();
            else if (isUndelete) domainConstructor.construct(newRecords).handleAfterUndelete(newRecordsMap);
	    }
        system.debug('**** END SObjectDomain.TriggerHandler()' + ' ****');
	}
    
}



/**
 * 
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
 * Base class aiding in the implemetnation of a Domain Model around SObject collections
 * 
 * Domain (software engineering). “a set of common requirements, terminology, and functionality 
 * for any software program constructed to solve a problem in that field”,
 * http://en.wikipedia.org/wiki/Domain_(software_engineering)
 *
 * Domain Model, “An object model of the domain that incorporates both behavior and data.”, 
 * “At its worst business logic can be very complex. Rules and logic describe many different "
 * "cases and slants of behavior, and it's this complexity that objects were designed to work with...” 
 * Martin Fowler, EAA Patterns
 * http://martinfowler.com/eaaCatalog/domainModel.html
 *
 **/