package entschema

import (
	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
)

// ImageReplication holds the schema definition for the ImageReplication entity.
type ImageReplication struct {
	ent.Schema
}

// Annotations of the ImageReplication.
func (ImageReplication) Annotations() []schema.Annotation {
	return []schema.Annotation{
		entsql.Annotation{Table: "image_replication"},
	}
}

// Fields of the ImageReplication.
func (ImageReplication) Fields() []ent.Field {
	return []ent.Field{
		field.Uint64("id").
			Positive(),
		field.Uint64("image_definition_id").
			Positive(),
		field.String("image_version").
			MaxLen(32),
		field.Text("replication_data"),
	}
}

// Indexes of the ImageReplication.
func (ImageReplication) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("image_definition_id", "image_version").Unique().StorageKey("by_id_version"),
	}
}
