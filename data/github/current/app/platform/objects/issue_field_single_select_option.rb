# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldSingleSelectOption < Platform::Objects::Base
      docs_category :issues
      scopeless_tokens_as_minimum
      description "Represents an option in a single-select issue field."

      # rubocop:disable GitHub/GraphqlAuthorizationMethodsArentCalled

      # When accessed through a field value (IssueFieldOptionWithFieldValueContext), authorize
      # via read_issue_field_values. Otherwise use the field-definition path (read_issue_fields).
      sig { params(permission: T.untyped, object: T.untyped).returns(T.untyped) }
      def self.async_api_can_access?(permission, object)
        if object.is_a?(Platform::Models::IssueFieldOptionWithFieldValueContext)
          Platform::Helpers::IssueFieldValue.async_api_can_access?(permission, object.field_value)
        else
          Platform::Helpers::IssueField.async_api_can_access?(permission, object)
        end
      end

      sig { params(permission: T.untyped, object: T.untyped).returns(T.untyped) }
      def self.async_viewer_can_see?(permission, object)
        if object.is_a?(Platform::Models::IssueFieldOptionWithFieldValueContext)
          Platform::Helpers::IssueFieldValue.async_viewer_can_see?(permission, object.field_value)
        else
          Platform::Helpers::IssueField.async_viewer_can_see?(permission, object)
        end
      end

      # rubocop:enable GitHub/GraphqlAuthorizationMethodsArentCalled

      database_id_field
      full_database_id_field

      field :name, String, "The option's name.", null: false
      field :description, String, "The option's plain-text description.", null: true
      field :color, Enums::IssueFieldSingleSelectOptionColor, "The option's display color.", null: false
      field :priority, Integer, "The option's priority order.", null: true

      implements_node templates: [[:ifsso, :id]], as: "IFSSO", ready_date: "1970-01-01" do |issue_field_single_select_option|
        {
          prefix: :ifsso,
          id: issue_field_single_select_option.id
        }
      end

      sig { params(id: T.any(Integer, String)).returns(Promise[T.nilable(Platform::Models::IssueFieldOptionWithFieldContext)]) }
      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldOption, id.to_i, security_violation_behaviour: :nil).then do |option|
          next unless option
          # When the kill switch is active skip the parent-field load and return the raw option.
          next option unless IssueFieldsFeature.repo_issue_fields_enabled?

          # Load and owner-preload the parent field so the access check in async_viewer_can_see?
          # can call field.owner without triggering an AR association load inside GraphQL.
          Platform::Loaders::ActiveRecord.load(::IssueField, option.issue_field_id).then do |field|
            next unless field
            ::ActiveRecord::Associations::Preloader.new(records: [field], associations: :owner).call
            Platform::Models::IssueFieldOptionWithFieldContext.new(option, field: field)
          end
        end
      end

      def priority
        @object.priority
      end
    end
  end
end
