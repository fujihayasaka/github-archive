# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class BillingComponent < ApplicationComponent

      include Copilot::Purchase::Helpers

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :selected_account

      sig { params(selected_account: T.any(::Organization, ::Business)).void }
      def initialize(selected_account:)
        @selected_account = selected_account
      end

      sig { override.void }
      def before_render
        @user = T.let(current_user, T.nilable(::User))
      end

      sig { returns(T::Boolean) }
      def account_is_adminable_by_user?
        return false unless @user.present?

        if has_parent_enterprise?
          return T.must(T.cast(@selected_account, ::Organization).business).adminable_by?(@user)
        end

        true
      end

      sig { returns(T::Boolean) }
      def has_parent_enterprise?
        @selected_account.is_a?(::Organization) && @selected_account.business.present?
      end
    end
  end
end
