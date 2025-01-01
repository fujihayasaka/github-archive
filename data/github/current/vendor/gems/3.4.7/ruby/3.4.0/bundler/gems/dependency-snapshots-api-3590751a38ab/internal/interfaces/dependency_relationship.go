package interfaces

import "encoding/json"

type DependencyRelationship int

const (
	NoRelationship DependencyRelationship = iota
	Direct
	Indirect
)

var DependencyRelationshipNames = map[DependencyRelationship]string{
	NoRelationship: "",
	Direct:         "direct",
	Indirect:       "indirect",
}

var DependencyRelationshipValues = map[string]DependencyRelationship{
	"":         NoRelationship,
	"direct":   Direct,
	"indirect": Indirect,
}

func (r DependencyRelationship) String() string {
	return DependencyRelationshipNames[r]
}

func (r DependencyRelationship) MarshalJSON() ([]byte, error) {
	return json.Marshal(r.String())
}

func (r *DependencyRelationship) UnmarshalJSON(b []byte) error {
	var j string
	err := json.Unmarshal(b, &j)
	if err != nil {
		return err
	}
	// Note that if the string cannot be found then it will be set to the zero value, 'NoRelationship' in this case.
	*r = DependencyRelationshipValues[j]
	return nil
}
