package types

import (
	"fmt"

	"github.com/twitchtv/twirp"
)

func NewPathspec(items ...*PathspecItem) *Pathspec {
	return &Pathspec{Items: items}
}

func (p *Pathspec) Validate() error {
	if p == nil {
		return nil
	}

	for _, item := range p.GetItems() {
		if err := item.Validate(); err != nil {
			return err
		}
	}

	return nil
}

func NewPathspecItem(patternType PathspecItem_PatternType, patterns ...*Pattern) *PathspecItem {
	return &PathspecItem{
		Patterns:    patterns,
		PatternType: patternType,
	}
}

func (item *PathspecItem) WithIgnoreCase() *PathspecItem {
	if item == nil {
		return nil
	}
	item.IgnoreCase = true
	return item
}

func (item *PathspecItem) WithExclude() *PathspecItem {
	if item == nil {
		return nil
	}
	item.Exclude = true
	return item
}

func (item *PathspecItem) Validate() error {
	if item == nil {
		return nil
	}

	if item.GetPatternType() == PathspecItem_PATTERN_TYPE_INVALID {
		return twirp.InvalidArgumentError("pattern_type", "must be one of: literal, glob, wildcard")
	}

	for i, pattern := range item.GetPatterns() {
		if pattern == nil {
			return twirp.RequiredArgumentError(fmt.Sprintf("patterns[%d]", i))
		}
		if err := pattern.Validate(); err != nil {
			return err
		}
		if pattern.GetPattern()[0] == ':' {
			return twirp.InvalidArgumentError(fmt.Sprintf("patterns[%d]", i), "cannot start with a colon")
		}
	}

	return nil
}
