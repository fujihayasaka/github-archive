package interfaces

import (
	"encoding/json"
)

type DependencyScope int

const (
	NoScope DependencyScope = iota
	Runtime
	Development
)

var DependencyScopeNames = map[DependencyScope]string{
	NoScope:     "",
	Runtime:     "runtime",
	Development: "development",
}

var DependencyScopeValues = map[string]DependencyScope{
	"":            NoScope,
	"runtime":     Runtime,
	"development": Development,
}

func (s DependencyScope) String() string {
	return DependencyScopeNames[s]
}

func (s DependencyScope) MarshalJSON() ([]byte, error) {
	return json.Marshal(s.String())
}

func (s *DependencyScope) UnmarshalJSON(b []byte) error {
	var j string
	err := json.Unmarshal(b, &j)
	if err != nil {
		return err
	}
	// Note that if the string cannot be found then it will be set to the zero value, 'NoScope' in this case.
	*s = DependencyScopeValues[j]
	return nil
}
