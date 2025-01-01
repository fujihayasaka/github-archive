package entschema

import (
	"time"

	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
)

// AzureSubscription holds the schema definition for the AzureSubscription entity.
type AzureSubscription struct {
	ent.Schema
}

func (AzureSubscription) Annotations() []schema.Annotation {
	return []schema.Annotation{
		entsql.Annotation{Table: "azure_subscription"},
	}
}

// Fields of the AzureSubscription.
func (AzureSubscription) Fields() []ent.Field {
	return []ent.Field{
		field.Uint64("id").
			Positive(),
		field.String("subscription_id").
			MaxLen(36).
			Default("unknown"),
		field.Enum("image_type").
			Values("Curated", "Customer", "Mixed"),
		field.String("resources_prefix").
			MaxLen(30),
		field.Time("created_at").
			Default(time.Now),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now),
		field.Uint("image_versions_count").
			Default(0),
		field.Uint("image_versions_limit").
			Default(0),
	}
}

func (AzureSubscription) Indexes() []ent.Index {
	return []ent.Index{
		// non-unique index.
		index.Fields("subscription_id").Unique().StorageKey("by_subscription_id"),
		index.Fields("image_type").StorageKey("by_image_type"),
	}
}
