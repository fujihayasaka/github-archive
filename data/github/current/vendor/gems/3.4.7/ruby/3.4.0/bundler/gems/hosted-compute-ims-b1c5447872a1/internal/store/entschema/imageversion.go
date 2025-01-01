package entschema

import (
	"time"

	"entgo.io/ent/schema/edge"

	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
)

// ImageVersion holds the schema definition for the ImageVersion entity.
type ImageVersion struct {
	ent.Schema
}

func (ImageVersion) Annotations() []schema.Annotation {
	return []schema.Annotation{
		entsql.Annotation{Table: "image_version"},
	}
}

// Fields of the ImageVersion.
func (ImageVersion) Fields() []ent.Field {
	return []ent.Field{
		field.Uint64("id").
			Positive(),
		field.String("version").
			MaxLen(32),
		field.Uint64("image_definition_id").
			Positive(),
		field.Enum("state").
			Values("Pending", "Provisioning", "Ready", "ProvisionFailed", "Deleting"),
		field.Text("state_details").Optional().Default("").
			MaxLen(1024),
		field.Bool("enabled").
			Default(true),
		field.Int32("size_gb").
			Optional().
			Nillable(),
		field.String("resource_id").
			Default("").
			MaxLen(1024),
		field.Time("created_at").
			Default(time.Now),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now),
	}
}

func (ImageVersion) Indexes() []ent.Index {
	return []ent.Index{
		// non-unique index.
		index.Fields("image_definition_id").StorageKey("by_image_definition_id"),
		index.Fields("version", "image_definition_id").Unique().StorageKey("by_version_image_definition_id"),
	}
}

func (ImageVersion) Edges() []ent.Edge {
	return []ent.Edge{
		edge.From("image_definition", ImageDefinition.Type).
			Ref("image_version").
			Field("image_definition_id").Unique().Required(),
	}
}
