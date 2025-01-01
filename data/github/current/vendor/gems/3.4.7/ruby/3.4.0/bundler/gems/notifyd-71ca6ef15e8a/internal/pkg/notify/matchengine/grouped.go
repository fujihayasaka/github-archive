package matchengine

/*
GroupedAttributes represents a map of subscription attributes to match.
There can be multiple attribute values therefore each map entry maps attribute name to a list of values.

	{
	  "attribute1_name" => ["value1", "value2"],
	  "attribute2_name" => ["value3", "value4"]
	}
*/
type GroupedAttributes map[string][]string

/*
GroupedMatchRule represents a rule that maps to a list of attributes to match using this rule.

	{
	  "match_rule" => {
	    "attribute1_name" => ["value1", "value2"],
	    "attribute2_name" => ["value3", "value4"]
	  }
	}

Example:

	{
	  "eq" => {
	    "has_label" => ["1", "2"]
	  }
	}
*/
type GroupedMatchRule map[string]GroupedAttributes

func (g *GroupedMatchRule) addMatchRule(attributeName, attributeValue, matchRule string) {
	if _, ok := (*g)[matchRule]; !ok {
		(*g)[matchRule] = GroupedAttributes{}
	}

	if _, ok := (*g)[matchRule][attributeName]; !ok {
		(*g)[matchRule][attributeName] = []string{}
	}

	(*g)[matchRule][attributeName] = append((*g)[matchRule][attributeName], attributeValue)
}
