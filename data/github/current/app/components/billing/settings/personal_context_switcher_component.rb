# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class PersonalContextSwitcherComponent < ApplicationComponent
      include SettingsHelper
      include SvgHelper

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      def render?
        return false if GitHub.enterprise?

        !account.organization?
      end

      def account_has_or_manages_orgs?
        orgs_count_managed_or_owned_by_account > 0
      end

      def orgs_count_managed_or_owned_by_account
        orgs_managed_or_owned_by_account.size
      end

      def include_filter?
        orgs_count_managed_or_owned_by_account > SettingsHelper::CONTEXT_DROPDOWN_MIN
      end

      private

      memoize def orgs_managed_or_owned_by_account
        available_contexts(current_context: account)
      end
    end
  end
end
