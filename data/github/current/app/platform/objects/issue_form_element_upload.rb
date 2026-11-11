# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFormElementUpload < Platform::Objects::Base
      extend IssueFormElementShortcuts

      visibility :under_development

      description "Upload element in an issue form"

      model_name "Upload"

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

      field :label, String, "A brief description of the expected user input, which is also displayed in the form.", null: false
      field :required, Boolean, "Prevents form submission until element is completed. Only for public repositories.", null: true
      field :accept, String, "A comma-separated list of file types that are accepted by the upload element.", null: true

      sig { returns(T::Boolean) }
      def required
        object.validations&.dig("required") == true
      end

      sig { returns(T.nilable(String)) }
      def accept
        object.validations&.dig("accept")
      end
    end
  end
end
