# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # These methods are added to Object and Interface DSLs for adding these common fields.
      module FieldShortcuts
        def database_id_field(**extra_kwargs)
          T.bind(self, T.all(GraphQL::Schema::Member::HasFields, Module))
          field(:database_id, Integer, null: true, description: "Identifies the primary key from the database.", **extra_kwargs)
          include(DatabaseIdField)
        end

        module DatabaseIdField
          extend T::Helpers

          requires_ancestor { GraphQL::Schema::Object }

          def database_id
            T.bind(self, GraphQL::Schema::Object)
            object.id
          end
        end

        def full_database_id_field(**extra_kwargs)
          T.bind(self, T.all(GraphQL::Schema::Member::HasFields, Module))
          field(:full_database_id, Platform::Scalars::BigInt, null: true, description: "Identifies the primary key from the database as a BigInt.", **extra_kwargs)
          include(FullDatabaseIdField)
        end

        module FullDatabaseIdField
          extend T::Helpers

          requires_ancestor { GraphQL::Schema::Object }

          def full_database_id
            T.bind(self, GraphQL::Schema::Object)
            object.id
          end
        end

        def created_at_field(**extra_kwargs)
          T.bind(self, GraphQL::Schema::Member::HasFields)
          field :created_at, Platform::Scalars::DateTime, null: false,
            description: "Identifies the date and time when the object was created.",
            **extra_kwargs
        end

        def updated_at_field(**extra_kwargs)
          T.bind(self, GraphQL::Schema::Member::HasFields)
          field :updated_at, Platform::Scalars::DateTime, null: false,
            description: "Identifies the date and time when the object was last updated.",
            **extra_kwargs
        end

        def deleted_at_field
          T.bind(self, GraphQL::Schema::Member::HasFields)
          field :deleted_at, Platform::Scalars::DateTime, null: true,
            description: "Identifies the date and time when the object was deleted."
        end
      end
    end
  end
end
