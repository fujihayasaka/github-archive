package v210turboscan

import (
	"github.com/pkg/errors"
)

func (r *Run) validateRules() error {
	if r.Tool == nil || r.Tool.Driver == nil {
		return nil
	}
	for _, rule := range r.Tool.Driver.Rules {
		if rule == nil {
			return errors.New("nil rule found in rule list")
		}
	}
	return nil
}
