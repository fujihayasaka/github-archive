# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ActionsStatus < Platform::Objects::Base
      description "The status of GitHub Actions for a repository"

      visibility :internal

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      minimum_accepted_scopes ["site_admin"]

      def self.async_viewer_can_see?(permission, _object)
        # TODO this object will never be public
        permission.hidden_from_public?(self)
      end

      def self.async_api_can_access?(permission, _object)
        # TODO this object will never be public
        permission.hidden_from_public?(self)
      end

      field :is_allowed, Boolean, description: "Returns whether or not GitHub Actions is allowed to run", null: false
      def is_allowed
        @object.async_customer.then do |customer|
          if customer.present?
            customer.async_payment_method.then do
              Billing::ActionsPermission.new(@object).allowed?
            end
          else
            false
          end
        end
      end

      field :error, Platform::Objects::ActionsStatusError, description: "The error representing why GitHub Actions is disabled", null: true

      def error
        @object
      end
    end
  end
end
