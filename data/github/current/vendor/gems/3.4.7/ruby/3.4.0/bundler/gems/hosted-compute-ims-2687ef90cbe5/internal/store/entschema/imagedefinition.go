package entschema

import (
	"time"

	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
)

// ImageDefinition holds the schema definition for the ImageDefinition entity.
type ImageDefinition struct {
	ent.Schema
}

func (ImageDefinition) Annotations() []schema.Annotation {
	return []schema.Annotation{
		entsql.Annotation{Table: "image_definition"},
	}
}

// Fields of the ImageDefinition.
func (ImageDefinition) Fields() []ent.Field {
	return []ent.Field{
		field.Uint64("id").
			Positive(),
		field.String("owner_id").
			MaxLen(128).
			Default("unknown"),
		field.String("name").
			MaxLen(256).
			Default("unknown"),
		field.Enum("image_type").
			Values("Curated", "Customer"),
		field.Bool("enabled").
			Default(true),
		field.String("feature_flag").
			MaxLen(128).
			Nillable().
			Optional(),
		field.Enum("os_type").
			Values("Linux", "Windows", "MacOS"),
		field.Enum("architecture").
			Values("X64", "Arm64"),
		field.Time("created_at").
			Default(time.Now),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now),
		field.Uint64("points_to_image_definition_id").
			Positive().
			Nillable().
			Optional(),
		field.Enum("state").
			Values("Ready", "Deleting").
			Default("Ready"),
		field.Uint64("runner_group_id").
			Positive().
			Nillable().
			Optional(),
		field.Bool("is_image_generation_supported").
			Default(false),
	}
}

func (ImageDefinition) Edges() []ent.Edge {
	return []ent.Edge{
		edge.To("image_version", ImageVersion.Type),
	}
}

func (ImageDefinition) Indexes() []ent.Index {
	return []ent.Index{
		// non-unique index.
		index.Fields("owner_id", "image_type").StorageKey("by_owner_id_image_type"),
		index.Fields("image_type").StorageKey("by_image_type"),
	}
}
