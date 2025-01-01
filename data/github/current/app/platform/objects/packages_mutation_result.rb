# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackagesMutationResult < Platform::Objects::Base
      description "Represents a mutation result for a Packages-related mutation."

      visibility :internal
      minimum_accepted_scopes ["read:packages"]

      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      def self.async_viewer_can_see?(permission, object)
        permission.hidden_from_public?(self)
      end

      field :success, Boolean, description: "Boolean flag indicating whether the mutation succeeded or not.", null: false
      field :user_safe_status, Integer, description: "The most appropriate HTTP status code to return to the end user.", null: false
      field :user_safe_message, String, description: "A safe summary message of what went wrong to show the end user.", null: false
      field :error_type, Enums::PackagesErrorType, description: "The high-level type of error that occurred.", null: false
      field :validation_errors, [Platform::Interfaces::UserError], description: "If the mutation fails due to invalid inputs, errors will show up in this list.", null: false

      def success
        !!@object[:success]
      end

      def user_safe_status
        status = @object[:user_safe_status] || 200
        case status
        when Symbol
          Rack::Utils.status_code(status)
        else
          status
        end
      end

      def user_safe_message
        @object[:user_safe_message] || ""
      end

      def error_type
        @object[:error_type] || "none"
      end

      def validation_errors
        @object[:validation_errors] || []
      end
    end
  end
end
