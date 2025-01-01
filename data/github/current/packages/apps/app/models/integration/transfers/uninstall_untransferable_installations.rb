# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class UninstallUntransferableInstallations

      sig { returns(Integration) }
      attr_reader :integration

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :target

      sig { returns(User) }
      attr_reader :requester

      sig { returns(String) }
      attr_reader :initial_visibility

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :initial_integration_owner

      sig { returns(T::Boolean) }
      attr_reader :staff_initiated

      sig { params(integration: Integration, target: T.any(User, Organization, Business), requester: User, initial_visibility: String, initial_owner: T.any(User, Organization, Business), staff_initiated: T::Boolean).void }
      def initialize(integration:, target:, requester:, initial_visibility:, initial_owner:, staff_initiated: false)
        @integration = integration
        @initial_integration_owner = initial_owner
        @target = target
        @requester = requester
        @initial_visibility = initial_visibility
        @staff_initiated = staff_initiated
      end

      sig { returns(T::Boolean) }
      def cannot_keep_installations_after_transfer?
        integration.installations.any? && private_app_cannot_keep_installations_after_transfer?
      end

      sig { void }
      def perform
        return unless cannot_keep_installations_after_transfer?

        integration.installations.take&.uninstall(actor: requester, staff_actor: staff_initiated)
      end

      private

      sig { returns(T::Boolean) }
      def private_app_cannot_keep_installations_after_transfer?
        return true if private_app_transferred_from_user_to_user?
        return true if private_app_transferred_from_user_to_org?
        return true if private_app_transferred_from_user_to_enterprise?

        return true if private_app_transferred_from_org_to_user?
        return true if private_app_transferred_from_org_to_org?

        false
      end

      sig { returns(T::Boolean) }
      def private_app_transferred_from_user_to_user?
        private_app? && transfer_from_user? && transfer_to_user?
      end

      sig { returns(T::Boolean) }
      def private_app_transferred_from_user_to_org?
        private_app? && transfer_from_user? && transfer_to_org?
      end

      sig { returns(T::Boolean) }
      def private_app_transferred_from_user_to_enterprise?
        private_app? && transfer_from_user? && transfer_to_enterprise?
      end

      sig { returns(T::Boolean) }
      def private_app_transferred_from_org_to_user?
        private_app? && transfer_from_org? && transfer_to_user?
      end

      sig { returns(T::Boolean) }
      def private_app_transferred_from_org_to_org?
        private_app? && transfer_from_org? && transfer_to_org?
      end

      sig { returns(T::Boolean) }
      def private_app?
        initial_visibility == "private_visibility"
      end

      sig { returns(T::Boolean) }
      def transfer_to_user?
        target.user?
      end

      sig { returns(T::Boolean) }
      def transfer_to_org?
        target.organization?
      end

      sig { returns(T::Boolean) }
      def transfer_to_enterprise?
        target.business?
      end

      sig { returns(T::Boolean) }
      def transfer_from_user?
        initial_integration_owner.user?
      end

      sig { returns(T::Boolean) }
      def transfer_from_org?
        initial_integration_owner.organization?
      end

    end
  end
end
