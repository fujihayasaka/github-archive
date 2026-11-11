# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFormElementDropdown < Platform::Objects::Base
      extend IssueFormElementShortcuts

      visibility :under_development

      description "Dropdown element in an issue form"

      model_name "Dropdown"

      implements Interfaces::IssueFormElement

      sig { params(permission: T.untyped, _object: T.untyped).returns(T::Boolean) }
      def self.async_api_can_access?(permission, _object)
        # This is only called internally as a field in the IssueForm object
        # and visibility is pre-checked on the Repository object.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, object: T.untyped).returns(T::Boolean) }
      def self.async_viewer_can_see?(permission, object)
        # This is only called internally as a field in the IssueForm object
        # and visibility is pre-checked on the Repository object.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      description_field
      description_html_field

      field :label, String, "A brief description of the expected user input, which is displayed in the form.", null: false
      field :options, [String], "An array of options the user can choose from.", null: false
      field :default, Integer, "The index of the default option.", null: true
      field :multiple, Boolean, "	Determines if the user can select more than one option.", null: true
      # Currently all input validations only support the "required" key, so exposing it directly
      field :required, Boolean, "Prevents form submission until element is completed. Only for public repositories.", null: true
      sig { returns(T::Boolean) }
      def required
        object.validations&.dig("required") == true
      end
    end
  end
end
