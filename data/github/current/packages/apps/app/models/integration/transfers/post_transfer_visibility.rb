# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class PostTransferVisibility

      sig { returns(Integration) }
      attr_reader :integration

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :target

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :integration_owner


      sig { params(integration: Integration, target: T.any(User, Organization, Business)).void }
      def initialize(integration:, target:)
        @integration = integration
        @integration_owner = T.let(integration.owner, T.any(User, Organization, Business))
        @target = target
      end

      sig { returns(T::Boolean) }
      def update_required?
        transfer_to_enterprise? || transfer_from_enterprise?
      end

      sig { returns(String) }
      def new_visibility
        return "internal_visibility" if transfer_to_enterprise?

        if transfer_from_enterprise?
          if to_non_emu_user_or_org_without_installations?
            return "private_visibility"
          else
            return "public_visibility"
          end
        end

        integration.visibility
      end

      private

      sig { returns(T::Boolean) }
      def transfer_to_enterprise?
        target.business?
      end

      sig { returns(T::Boolean) }
      def transfer_from_enterprise?
        integration_owner.business?
      end

      sig { returns(T::Boolean) }
      def to_non_emu_user_or_org_without_installations?
        (to_user? || to_org?) && not_enterprise_managed? && without_installations?
      end

      sig { returns(T::Boolean) }
      def to_user?
        target.user?
      end

      sig { returns(T::Boolean) }
      def to_org?
        target.organization?
      end

      sig { returns(T::Boolean) }
      def not_enterprise_managed?
        !(target.organization? ? T.cast(target, Organization).enterprise_managed_user_enabled? : T.cast(target, User).is_enterprise_managed?)
      end

      sig { returns(T::Boolean) }
      def without_installations?
        integration.installations.none?
      end
    end
  end
end
