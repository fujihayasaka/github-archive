# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    module Helpers
      extend T::Helpers

      sig { params(account: T.any(::Organization, ::Business)).returns(String) }
      def account_name(account)
        if account.is_a?(::Business)
          account.slug
        else
          account.display_login
        end
      end

      sig { params(account: T.any(::Organization, ::Business)).returns(String) }
      def owning_account_name(account)
        return account.slug if account.is_a?(::Business)

        if account.business.present?
          T.must(account.business).slug
        else
          account.display_login
        end
      end

      sig { params(account: T.any(::Organization, ::Business)).returns(String) }
      def account_type(account)
        class_name = T.must(account.class.name)
        class_name == "Business" ? "Enterprise" : "Organization"
      end

      sig { params(this_account: T.nilable(T.any(::Organization, ::Business)), other_account: T::Hash[Symbol, String]).returns(T::Boolean) }
      def account_is_selected?(this_account, other_account)
        return false if this_account.nil?
        account_name(this_account) == other_account[:slug] && account_type(this_account) == other_account[:type]
      end
    end
  end
end
