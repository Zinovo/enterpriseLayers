/** 
 * 
 * @author Kevin Rice
 * @date 2017.06.12
 * @group Data Access Layer
 * @description Base abstract class that is utilized by extending classes to select records from SObjects (e.g. LeadSelector, AccountSelector, etc.). Only one public method
 * is exposed herein to query records by id. In order to form tight contracts with the caller, all extending classes will need to expose use-case specific methods to perform
 * more complex queries. 
 * Note that for query methods returning the generic List<SObject>, if relational objects/fields were included in the query, developers writing calling code will need to either: 
 * (1) Cast the returned results to the specific SObject type, such that the dot notation (e.g. Account.RecordType.Name) can be used to traverse the relational data, or 
 * (2) familiarize themselves with the Apex SObject class, particularly the getSObject(String fieldName), getSObjects(String fieldName), and get(String fieldName) methods, 
 * as of version 40.0, which allow for relational traversal via Dynamic DML without the need for type casting.    
 * 
 **/

public abstract class SObjectSelector {
    
    public Set<Schema.SObjectField> baseFields { get; protected set; }
    public Map<String,Schema.SObjectField> relatedFieldMap { get; protected set; }
    public String orderBy { get; protected set; }
    public Boolean isFLSEnforced { get; protected set; }
    public Boolean isOLSEnforced { get; protected set; }
    protected QueryUtil qutil; 
    
    /** @description No argument constructor. Enforces object-level-security (OLS) but not field-level-security (FLS) **/
    public SObjectSelector() {
        this(true, false); 
    }
    
    /** 
     * @description Default constructor.
	 * @param *doEnforceOLS* Boolean. When set to true, field level security for (OLS) the context user will be enforced. Default is true.  
	 * @param *doEnforceFLS* Boolean. When set to true, field level security for (FLS) the context user will be enforced. Default is false. Use caution when setting to true as doing so may result in
	 * runtime errors where there are dependencies on the fields called. 
     **/ 
    public SObjectSelector(Boolean doEnforceOLS, Boolean doEnforceFLS) { 
        
        // set ols and fls enforcement
        isOLSEnforced = (doEnforceOLS == null) ? true : doEnforceOLS; 
        isFLSEnforced = (doEnforceFLS == null) ? false : doEnforceFLS; 
        
        // if getSObjectType() is null, return early
        if (getSObjectType() == null) {
            String className; 
            try {
            	className = String.valueOf(this).split(':')[0];     
            } catch (Exception e) { }
            system.debug('Class ' + className + ' has returned null for the abstract method getSObjectType(). Runtime errors may occur unless property is set prior to query.'); 
            return; 
        }
        
        // if context user does not have read access to object, throw error
        if (doEnforceOLS && !getSObjectType().getDescribe().isAccessible()) {
            String errString = 'User ' + UserInfo.getUserName() + ' does not have read access to the ' + getSObjectName() + ' object.'; 
            UtilException ue = UtilException.errPretty(SObjectSelector.class, errString); 
            ue.debugPretty(); 
            throw ue; 
        }
        
        this.qutil = new QueryUtil(getSObjectType());
        this.orderBy = getOrderBy(); 
        this.baseFields = getBaseFields(); 
        // add all fields on the provided SObject where !isNillable 
        this.baseFields.addAll(getRequiredFields(getSObjectType())); 
        // if FLS is being enforced, remove any fields to which the current user does not have access
        if (doEnforceFLS) {
            enforceFLS(); 
        } 
    }
    
    /************************************ Static Methods ************************************/
    /*
     * @description Provided a list of SObjects, returns the MaxAccessLevel enum from the UserRecordAccess table.
     * @param *records* List<SObject>
     * @return *Map<Id,String>
     */
    public static Map<Id,RecordAccess> getRecordAccess(List<SObject> records, Id userId) {
        Map<Id,RecordAccess> access = new Map<Id,RecordAccess>(); 
        List<Id> recIds = new List<Id>(); 
        for (SObject sobj : records) {
            recIds.add(sobj.id); 
        }
        for (UserRecordAccess ura : [SELECT hasAllAccess, hasDeleteAccess, hasEditAccess, hasReadAccess, hasTransferAccess, maxAccessLevel, recordId
                                     FROM UserRecordAccess 
                                     WHERE recordId IN :recIds AND userId = :userId]) {
            access.put(ura.recordId, new RecordAccess(ura, userId)); 
        }
        return access; 
    }
    
    
    /************************************ Abstract and Virtual Methods ************************************/
    
    /**
     * @description Abstract. Concrete classes must provide implementation. Fields must all be "on-object" - no relational field references. 
     * To query relational fields, use setRelatedFields(). 
     * @return The base fields that will be included in all queries. 
     **/
    public abstract Set<Schema.SObjectField> getBaseFields(); 
    
    /**
     * @description Abstract. Concrete classes must provide implementation.
     * @return The SObjectType that will be queried and used as the SObject context for field validations, etc.
     **/
    public abstract Schema.SObjectType getSObjectType(); 
    
    /**
     * @description Virtual. Defines the sort order for the query. Default is by ' Name ASC'
     * @return String describing the SOQL sort order
     **/
    public virtual String getOrderBy() {
        return ' Name ASC'; 
    }
    
    /************************************ Public Methods providing implemenation************************************/
    
    /*
     * @description Allows caller to add all fields defined for the SObjectType. 
     */
    public void addAllFields() {
        addBaseFields( new Set<Schema.SObjectField>( getSObjectType().getDescribe().fields.getMap().values() ) );
    }
    
    /**
     * @description Allows the caller to add fields of the given SObjectType to the baseFields for query
     * @param *fields* List of Schema.SObjectFields, which must belong to the instance SObject, to query in addition to existing base fields
     **/
    public void addBaseFields(Set<Schema.SObjectField> fields) {
        if (fields == null) 
            return; 
        this.baseFields.addAll(fields);
        if (isFLSEnforced) 
            enforceFLS(); 
    }
    
    /**
     * @description Allows caller to add related object fields to the query. Fields may only traverse parent relationships (e.g. "upward"). Related child objects and fields cannot
     * be added. 
     * @param *pathsToFields* A map of the query path, as a string, to the SObjectField. The inclusion of the mapping to the explicit Schema.SObjectField ensures that 
     * fields will not accidentally be deleted, resulting in code breakage. Note that paths must be relevant to the SObject in context or queries will fail at runtime. See
     * examples below. 
     * @example
	 * // valid mapping for Account SObject
	 * Map<String,Schema.SObjectField> pathsToFields = new Map<String,Schema.SObjectField> { 'Account.RecordType.Name' => Account.RecordType.Name }
	 * // valid mapping for Contact SObject
	 * Map<String,Schema.SObjectField> pathsToFields = new Map<String,Schema.SObjectField> { 'Contact.Account.RecordType.Name' => Account.RecordType.Name }
     **/
    public void addRelatedFields(Map<String,Schema.SObjectField> pathsToFields) {
        if (this.relatedFieldMap == null) 
            this.relatedFieldMap = new Map<String,Schema.SObjectField>(); 
        this.relatedFieldMap.putAll(pathsToFields); 
    }
    
    /**
     * @description Performs the defined query for records matching the provided Ids 
     * @param *includeIds* a list of SObject Ids for the provided SObjectType to return
     * @return List of SObjects matching the provided Ids
     **/
    public List<SObject> getSObjectsById(List<Id> includeIds) { 
        List<String> istring = (List<String>)includeIds; 
        String idString = 'Id IN (\'' + (istring.size() == 1 ? istring[0] : String.join(istring,'\',\'')) + '\')'; 
        String query = String.format('SELECT {0}{1} FROM {2} WHERE {3} ORDER BY {4}',
                                     new List<String> {
                                         getObjectFields(),
                                         getRelatedFields(),
                                         getSObjectName(),
                                         idString,
                                         getOrderBy()
                                     });  
        return getSObjectList(query);  
    }
    
    /************************************ (Protected) Methods available to Concrete classes, but not publicly ************************************/

    protected void enforceFLS() {
        for (Schema.SObjectField sof : this.baseFields) {
            if (!sof.getDescribe().isAccessible()) {
                this.baseFields.remove(sof); 
            }
        }
    }
    
    protected String getObjectFields() {
        return qutil.getObjectFieldString(this.baseFields); 
    }
    
    protected String getRelatedFields() {
        if ((this.relatedFieldMap == null) || (this.relatedFieldMap.isEmpty())) {
            return ''; 
        } else {
            return qutil.getRelatedFieldString(this.relatedFieldMap,true); 
        }
    }
    
    protected List<Schema.SObjectField> getRequiredFields(Schema.SObjectType sob) {
        List<Schema.SObjectField> reqFields = new List<Schema.SObjectField>(); 
        for (schema.SObjectField field : sob.getDescribe().fields.getMap().values()) {
            DescribeFieldResult dfr = field.getDescribe();
            // ensure Id and lookupIds are always added to the query 
            if ( dfr.getName() == 'Id' || dfr.isIdLookup() ) {
                reqFields.add(field); 
                continue; 
            }
            if ( (!dfr.isNillable()) && (!dfr.isDefaultedOnCreate()) ) {
                reqFields.add(field); 
            }
        }
        return reqFields; 
    }
    
    protected String getSObjectName() {
        return getSObjectType().getDescribe().getName(); 
    }
    
    protected List<SObject> getSObjectsByWhere(String whereClauses) { 
        String query = String.format('SELECT {0}{1} FROM {2} WHERE {3} ORDER BY {4}',
                                     new List<String> {
                                         getObjectFields(),
                                         getRelatedFields(),
                                         getSObjectName(),
                                         whereClauses,
                                         getOrderBy()
                                     }); 
        return getSObjectList(query);
    }
    
    protected List<Sobject> getSObjectList(String query) {
        try {  
            List<SObject> results = Database.query(query); 
            system.debug('--' + results.size() + ' results for ' + getSObjectName() + ' (SObjectSelector) query: ' + query + '--');
            return results; 
        } catch (exception e) {
            UtilException ue = UtilException.errPretty(SObjectSelector.class, e.getMessage()); 
            throw ue; 
        }
    }
    
    /**
     * @description Allows the caller to designate related object fields to include in the query. 
     * @param *pathsToFields* A map of the query path, as a string, to the SObjectField. The inclusion of the mapping to the explicit Schema.SObjectField ensures that 
     * fields will not accidentally be deleted, resulting in code breakage. Note that paths must be relevant to the SObject in context or queries will fail at runtime. See
     * examples below. 
     * @example
	 * // valid mapping for Account SObject
	 * Map<String,Schema.SObjectField> pathsToFields = new Map<String,Schema.SObjectField> { 'Account.RecordType.Name' => Account.RecordType.Name }
	 * // invalid mapping for Account SObject - will fail at runtime
	 * Map<String,Schema.SObjectField> pathsToFields = new Map<String,Schema.SObjectField> { 'Contact.Account.RecordType.Name' => Account.RecordType.Name }
     **/
    protected void setRelatedFields(Map<String,Schema.SObjectField> pathsToFields) {
        this.relatedFieldMap = pathsToFields; 
    }
    
    /************************************ Inner Classes ************************************/
    public class RecordAccess {
        public Boolean hasAll, hasDelete, hasEdit, hasRead, hasTransfer;
        public String maxAccessLevel;
        public Id recordId; 
        public Id userId; 
        // constructor
        public RecordAccess(UserRecordAccess ura, Id userId) {
        	this.hasAll = ura.HasAllAccess; 
            this.hasDelete = ura.HasDeleteAccess;     
            this.hasEdit = ura.HasEditAccess; 
            this.hasRead = ura.HasReadAccess; 
            this.hasTransfer = ura.HasTransferAccess; 
            this.maxAccessLevel = ura.MaxAccessLevel;
            this.recordId = ura.RecordId; 
            this.userId = userId; 
        }
    }

}