package models

import "gopkg.in/guregu/null.v4"

type Business struct {
	ID        int64    `db:"id" json:"id"`
	Slug      string   `db:"slug" json:"slug"`
	Shortcode string   `db:"shortcode" json:"shortcode"`
	Spammy    null.Int `db:"spammy" json:"spammy"`
}
