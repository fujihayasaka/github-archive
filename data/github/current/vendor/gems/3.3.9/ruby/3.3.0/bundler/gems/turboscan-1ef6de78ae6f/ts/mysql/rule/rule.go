// Package rule contains a service that stores the rules used during a code scanning analysis.
package rule

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mysql/gormbulk"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/jinzhu/gorm"
)

type Service struct {
	db *gorm.DB
}

// NewService creates a new Servic
func NewService(db *gorm.DB) *Service {
	rs := &Service{
		db: db,
	}
	return rs
}

func ruleScope(db *gorm.DB, rule *ts.Rule) *gorm.DB {
	return db.Where("tool_id = ? AND sarif_identifier = ? AND hash = ?", rule.ToolID, rule.SarifIdentifier, rule.Hash)
}

func ruleTagScope(db *gorm.DB, ruleTag *ts.RuleTag) *gorm.DB {
	return db.Where("rule_id = ? AND tag = ?", ruleTag.RuleID, ruleTag.Tag)
}

// FindOrCreate syncs rules to the database
func (s *Service) FindOrCreate(ctx context.Context, rules []*ts.Rule) error {
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	err := gormbulk.InsertIgnore(ctx, ruleScope, &gormbulk.InsertOptions[ts.Rule]{
		DB:        db,
		ChunkSize: 500,
		Objects:   rules,
	})
	if err != nil {
		return err
	}

	tags := make([]*ts.RuleTag, 0)

	// update the relationship IDs here before bulk inserting
	for _, rule := range rules {
		for _, tag := range rule.Tags {
			tag.RuleID = rule.ID
			tags = append(tags, &tag)
		}
	}

	return gormbulk.InsertIgnore(ctx, ruleTagScope, &gormbulk.InsertOptions[ts.RuleTag]{
		DB:        db,
		ChunkSize: 500,
		Objects:   tags,
	})
}
