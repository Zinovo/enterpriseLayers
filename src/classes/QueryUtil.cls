/**
 * @author Kevin Rice
 * @date 2017.06.15
 * @group Utilities
 * @description Provides common utilities to classes building dynamic queries, e.g. for method calls such as Database.query(String queryString).
 **/

public class QueryUtil {
    
    private Schema.SObjectType sobj;  
    private Map<String,Schema.SObjectField> objFields = new Map<String,Schema.SObjectField>(); 
    
    public QueryUtil(Schema.SObjectType sobType) {
        this.sobj = sobType;
        this.objFields = sobType.getDescribe().fields.getMap(); 
    }

    /**
     * @description Returns a comma-separated list of values to retrieve. Validates all SObject fields in the fields param belong directly to sobj
     * @param *fields* Set of Schema.SObjectFields
     * @param *sobject* The SObject type of the SObject to which the fields belong
     * @return String of alpha-sorted, comma-separated fields for all valid SObjectFields passed in
     **/
    public String getObjectFieldString(Set<Schema.SObjectField> fields) {
        List<String> retFields = new List<String>(); 
        Set<Schema.SObjectField> sfields = new Set<Schema.SObjectField>(objFields.values());
        for (Schema.SObjectField sof : fields) {
            if (!sfields.contains(sof)) {
                 fields.remove(sof);  
            } else {
                retFields.add(sof.getDescribe().getName()); 
            }
        }
        retFields.sort();  
        return String.join(retFields, ', '); 
    }
    
    /**
     * @description When doValidate is set to true, validates that each String key in the map provides a valid path from the instance variable sobj to the matching 
     * Schema.SObjectField value. Else, returns a simple String of comma-separated values for each key. In current method version doValidate designation is ignored and
     * no validation takes place.  
     * @param *pathsToFields* String key of the query path for the current in-context SObject to the Schema.SObjectField value to which it corresponds 
     * @param *doValidate* Boolean. When set to true, key paths will be validated to ensure they correspond to the corresponding Schema.SObjectField key (future)
     * @example
     * // instance variable sobj is Schema.Account.SObjectType
     * // map that will validate
	 * Map<String,Schema.SObjectField> pathsToFields = new Map<String,Schema.SObjectField> { 'Account.RecordType.Name' => Account.RecordType.Name }
     **/
    public String getRelatedFieldString(Map<String,Schema.SObjectField> pathsToFields, Boolean doValidate) {
        String retString = ''; 
        if (doValidate) {
            // future
        } 
        List<String> keys = new List<String>(pathsToFields.keySet()); 
        if (keys.size() > 0) {
            retString += ',' + (keys.size() == 1 ? keys[0] : String.join(keys,', ')); 
        }
        return retString; 
    }
    
}