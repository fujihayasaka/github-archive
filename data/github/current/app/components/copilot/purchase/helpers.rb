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
    end
  end
end
