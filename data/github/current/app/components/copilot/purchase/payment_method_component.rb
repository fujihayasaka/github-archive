# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class PaymentMethodComponent < ApplicationComponent

      include GitHub::Memoizer

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

      sig { returns(::User) }
      def user
        T.must(@user)
      end

      sig { returns(T::Boolean) }
      def render?
        return false unless GitHub.billing_enabled?
        return false unless logged_in?
        return false if has_commercial_interaction_restriction?
        return false if has_linked_trade_screening_record_for_other_admin_but_no_payment_method?
        # We still want to show azure billing / linking information
        return false if selected_account.invoiced? && !selected_account.metered_via_azure?

        selected_account.has_saved_trade_screening_record?
      end

      sig { returns(T::Boolean) }
      memoize def has_commercial_interaction_restriction?
        user.has_commercial_interaction_restriction?(feature_type: :copilot)
      end

      sig { returns(T::Boolean) }
      memoize def has_linked_trade_screening_record?
        user.has_linked_trade_screening_record?
      end

      sig { returns(T::Boolean) }
      memoize def linked_trade_screening_record_belongs_to_current_user?
        return false if selected_account.is_a? ::Business
        user.has_trade_screening_record_linked_to_org?(organization: T.cast(selected_account, ::Organization))
      end

      sig { returns(T::Boolean) }
      memoize def has_linked_trade_screening_record_for_other_admin_but_no_payment_method?
        return false unless has_linked_trade_screening_record?
        return false if linked_trade_screening_record_belongs_to_current_user?
        return false if has_valid_payment_method?

        true
      end

      sig { returns(T::Boolean) }
      memoize def has_valid_payment_method?
        selected_account.has_valid_payment_method?
      end
    end
  end
end
