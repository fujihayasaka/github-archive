# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        module FieldValues
          # FieldIdProperty stores information on how a field should be serialized when generating the field values
          # for a project item in Elasticsearch. Depending on whether or not a field is referencing a
          # `MemexProjectColumn` that is referencing an `IssueField` or not, the `field_values` serialization
          # will differ.
          #
          # Example:
          #
          #   field_id = Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty::ProjectFieldId.new(1234)
          #   field_value = Elastomer::Interfaces::Document::MemexProjectItem::FieldValue.new(
          #     field_slug: "title",
          #     field_type: "title",
          #     field_id:,
          #     value_name: "title_value",
          #     value: "monalisa",
          #   )
          #
          #   field_id.property
          #   # => :field_id
          #
          #   field_id.value
          #   # => 1234
          #
          #   field_value.to_hash
          #   # => {
          #     "field_slug": "title",
          #     "field_type": "title",
          #     "field_id": 1234,
          #     "title_value": "monalisa"
          #   }
          #
          # Example:
          #
          #   field_id = Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty::IssueFieldId.new(4321)
          #   field_value = Elastomer::Interfaces::Document::MemexProjectItem::FieldValue.new(
          #     field_slug: "dri",
          #     field_type: "text",
          #     field_id:,
          #     value_name: "issue_field_text_value",
          #     value: "monalisa",
          #   )
          #
          #   field_id.property
          #   # => :issue_field_id
          #
          #   field_id.value
          #   # => 4321
          #
          #   field_value.to_hash
          #   # => {
          #     "field_slug": "dri",
          #     "field_type": "text",
          #     "issue_field_text_value": "monalisa",
          #     "issue_field_id": 4321
          #   }
          module FieldIdProperty
            extend T::Helpers
            sealed!
            abstract!

            # The canonical identifier for the current field's `field_values` object. This is typically the database
            # ID of the field.
            #
            # Example:
            #
            #   field_id = Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty::ProjectFieldId.new(1234)
            #   field_id.id
            #   # => 1234
            sig { abstract.returns(Integer) }
            def id; end

            # The property used for the current field's canonical identifier (see `id`) in the `field_values` object.
            #
            # Example:
            #
            #   field_id = Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty::ProjectFieldId.new(1234)
            #   field_id.property
            #   # => :field_id
            #
            #   field_id = Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty::IssueFieldId.new(4321)
            #   field_id.property
            #   # => :issue_field_id
            sig { abstract.returns(Symbol) }
            def property; end

            # `IssueFieldId` represents the name of the property used within the `field_values` object when indexing an
            # `IssueField` field value for a project item.
            #
            # Example:
            #
            #   {
            #     "field_slug": "dri",
            #     "field_type": "text",
            #     "issue_field_text_value": "monalisa",
            #     "issue_field_id": 1
            #   }
            class IssueFieldId
              include FieldIdProperty

              sig { override.returns(Symbol) }
              attr_reader :property

              sig { override.returns(Integer) }
              attr_reader :id

              sig { params(id: Integer).void }
              def initialize(id)
                @property = T.let(:issue_field_id, Symbol)
                @id = id
              end
            end

            # `ProjectFieldId` represents the name of the property used within the `field_values` object when
            # indexing a non-IssueField field value for a project item.
            #
            # Example:
            #
            #   {
            #     "field_slug": "sub-issues-progress",
            #     "field_type": "sub_issues_progress",
            #     "sub_issues_progress_value": {
            #       "total": 1,
            #       "percent_completed": 0
            #     },
            #     "field_id": 14
            #   }
            class ProjectFieldId
              include FieldIdProperty

              sig { override.returns(Symbol) }
              attr_reader :property

              sig { override.returns(Integer) }
              attr_reader :id

              sig { params(id: Integer).void }
              def initialize(id)
                @property = T.let(:field_id, Symbol)
                @id = id
              end
            end
          end
        end
      end
    end
  end
end
