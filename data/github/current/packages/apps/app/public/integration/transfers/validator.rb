# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class Validator

      sig { returns(Integration) }
      attr_reader :integration

      sig { returns(T.nilable(T.any(User, Organization, Business))) }
      attr_reader :target

      sig { returns(T::Boolean) }
      attr_reader :stafftools_initiated

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :app_owner

      sig { params(integration: Integration, target: T.nilable(T.any(User, Organization, Business)), stafftools_initiated: T::Boolean).void }
      def initialize(integration:, target:, stafftools_initiated:)
        @integration = integration
        @target = target
        @stafftools_initiated = stafftools_initiated
        @app_owner = T.let(integration.owner, T.any(User, Organization, Business))
      end

      sig { returns(T::Boolean) }
      def valid?
        return false if target_does_not_exist?
        return false if self_transfer_restricted?
        return false if cross_emu_transfer_restricted?
        return false if transfer_to_business_restricted?

        true # \o/
      end

      private

      sig { returns(T::Boolean) }
      def target_does_not_exist?
        target.blank?
      end

      sig { returns(T::Boolean) }
      def self_transfer_restricted?
        app_owner == target
      end

      sig { returns(T::Boolean) }
      def cross_emu_transfer_restricted?
        !integration.valid_target?(T.must(target))
      end

      sig { returns(T::Boolean) }
      def transfer_to_business_restricted?
        return true if public_app_transfer_to_business_restricted?
        return true if user_to_unaffiliated_business_transfer_restricted?
        return true if org_to_unaffiliated_business_transfer_restricted?
        return true if non_stafftools_biz_to_biz_transfer?
        return true if stafftools_biz_to_biz_transfer_with_installations?

        false
      end

      sig { returns(T::Boolean) }
      def public_app_transfer_to_business_restricted?
        !emu_user_or_org_owner? && (integration.public_visibility? && transfer_to_business?)
      end

      sig { returns(T::Boolean) }
      def emu_user_or_org_owner?
        case app_owner
        when Organization
          T.cast(app_owner, Organization).enterprise_managed_user_enabled?
        when User
          T.cast(app_owner, User).is_enterprise_managed?
        else
          false
        end
      end

      sig { returns(T::Boolean) }
      def user_to_unaffiliated_business_transfer_restricted?
        return false if stafftools_initiated

        # User owned apps can only transfer to enterprises the user belongs to
        app_owner.user? && transfer_to_business? && !T.cast(target, Business).async_member?(app_owner).sync
      end

      sig { returns(T::Boolean) }
      def org_to_unaffiliated_business_transfer_restricted?
        return false if stafftools_initiated

        # Organizations can only transfer to their own enterprise
        if app_owner.organization? && transfer_to_business?
          org_biz = T.cast(app_owner, Organization).business
          return true unless org_biz == target
        end

        false
      end

      sig { returns(T::Boolean) }
      def non_stafftools_biz_to_biz_transfer?
        return false unless app_owner.business? && transfer_to_business?
        !stafftools_initiated
      end

      sig { returns(T::Boolean) }
      def stafftools_biz_to_biz_transfer_with_installations?
        stafftools_initiated && transfer_from_business? && transfer_to_business? && integration.installations.any?
      end

      sig { returns(T::Boolean) }
      def transfer_from_business?
        app_owner.business?
      end

      sig { returns(T::Boolean) }
      def transfer_to_business?
        target&.business?
      end

    end
  end
end
