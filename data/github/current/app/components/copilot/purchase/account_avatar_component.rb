# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class AccountAvatarComponent < ApplicationComponent
      include GitHub::Memoizer
      include Copilot::Purchase::Helpers

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :account

      sig { returns(T::Boolean) }
      attr_reader :show_account_info

      sig { params(account: T.any(::Organization, ::Business), show_account_info: T::Boolean, use_owner: T::Boolean).void }
      def initialize(account:, show_account_info: true, use_owner: false)
        @account = account
        @show_account_info = show_account_info
        @use_owner = use_owner
      end

      sig { returns(String) }
      def avatar_url
        helpers.avatar_url_for(account)
      end

      sig { returns(String) }
      def child_entities_string
        if account.is_a?(::Business)
          org_count_string
        else
          member_count_string
        end
      end

      sig { returns(String) }
      memoize def member_count_string
        pluralize(account.members.count, "member")
      end

      sig { returns(String) }
      memoize def org_count_string
        pluralize(account.organizations.count, "organization")
      end

      sig { returns(String) }
      def name
        if @use_owner
          owning_account_name(account)
        else
          account_name(account)
        end
      end
    end
  end
end
