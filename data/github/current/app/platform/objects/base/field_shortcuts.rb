# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # These methods are added to Object and Interface DSLs for adding these common fields.
      module FieldShortcuts
        def database_id_field(**extra_kwargs)
          field(:database_id, Integer, null: true, description: "Identifies the primary key from the database.", **extra_kwargs)
          include(DatabaseIdField)
        end

        module DatabaseIdField
          def database_id
            object.id
          end
        end

        def full_database_id_field(**extra_kwargs)
          field(:full_database_id, Platform::Scalars::BigInt, null: true, description: "Identifies the primary key from the database as a BigInt.", **extra_kwargs)
          include(FullDatabaseIdField)
        end

        module FullDatabaseIdField
          def full_database_id
            object.id
          end
        end

        def created_at_field(**extra_kwargs)
          field :created_at, Platform::Scalars::DateTime, null: false,
            description: "Identifies the date and time when the object was created.",
            **extra_kwargs
        end

        def updated_at_field(**extra_kwargs)
          field :updated_at, Platform::Scalars::DateTime, null: false,
            description: "Identifies the date and time when the object was last updated.",
            **extra_kwargs
        end

        def deleted_at_field
          field :deleted_at, Platform::Scalars::DateTime, null: true,
            description: "Identifies the date and time when the object was deleted."
        end
      end
    end
  end
end
