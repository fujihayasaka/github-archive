package workflowparser

import (
	"errors"
	"strings"
)

// Convenience for YAML configurations that allow strings or list of strings
// This type will parse to a slice of strings in both cases
type stringList []string

func (l *stringList) IsPresent() bool {
	return l != nil
}

func (l *stringList) Value() []string {
	if l == nil {
		return []string{}
	}
	return *l
}

func (l *stringList) LowerCaseValue() []string {
	lcValues := []string{}
	if l != nil {
		for _, val := range *l {
			lcValues = append(lcValues, strings.ToLower(val))
		}
	}

	return lcValues
}

func (l *stringList) UnmarshalYAML(unmarshal func(any) error) error {
	if str, err := unmarshalString(unmarshal); err == nil {
		*l = []string{str}
		return nil
	}

	if sl, err := unmarshalStringSlice(unmarshal); err == nil {
		*l = sl
		return nil
	}

	return errors.New("Invalid type in stringList")
}

func unmarshalString(unmarshal func(any) error) (string, error) {
	var str string
	err := unmarshal(&str)
	return str, err
}

func unmarshalStringSlice(unmarshal func(any) error) ([]string, error) {
	var sl []string
	err := unmarshal(&sl)
	return sl, err
}
