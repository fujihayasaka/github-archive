# typed: strict
# frozen_string_literal: true

module Sponsors
  module Orgs
    class InvoicedBilling::AccountSwitcherComponent < ApplicationComponent
      include SettingsHelper

      FILTER_THRESHOLD = 10

      sig { params(selected_account: Organization).void }
      def initialize(selected_account:)
        @selected_account = selected_account
      end

      private

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      sig { returns(Organization) }
      attr_reader :selected_account

      sig { returns(T::Array[Integer]) }
      memoize def available_organization_ids
        current_user.owned_or_billing_manager_organization_ids - [selected_account.id]
      end

      sig { returns(T::Array[Organization]) }
      memoize def available_organizations
        Organization.where(id: available_organization_ids).reject { |org| org.deleted? }
      end

      sig { returns(T::Boolean) }
      def show_dropdown?
        available_organizations.any?
      end

      sig { returns(T::Boolean) }
      def include_filter?
        available_organizations.size > FILTER_THRESHOLD
      end
    end
  end
end
