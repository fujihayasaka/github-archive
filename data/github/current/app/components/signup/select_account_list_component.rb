# typed: true
# frozen_string_literal: true

module Signup
  class SelectAccountListComponent < ApplicationComponent

    class AccountType < T::Enum
      enums do
        Org = new("org")
        Business = new("business")
      end

      def to_s
        serialize
      end
    end

    attr_reader :accounts, :benefit, :account_type

    sig { params(accounts: T.any(T::Array[Organization], T::Array[Business], ActiveRecord::Relation), account_type: AccountType, benefit: T.nilable(String)).void }
    def initialize(accounts:, account_type:, benefit: nil)
      @accounts = accounts
      @account_type = account_type
      @benefit = benefit
    end

    private

    sig { returns(T::Boolean) }
    def render?
      return false if GitHub.single_business_environment?
      return false unless user_feature_enabled?(:dfd_get_started_with_copilot)
      return false if @accounts.first&.is_a?(Business) && @account_type == AccountType::Org
      return false if @accounts.first&.is_a?(Organization) && @account_type == AccountType::Business
      true
    end

    def frame_id
      if @account_type == AccountType::Org
        "orgs_list"
      else
        "business_list"
      end
    end

    def search_text
      if @account_type == AccountType::Org
        "organizations"
      else
        "enterprises"
      end

    end

    def query_path
      if @account_type == AccountType::Org
        signup_orgs_path(with: @benefit)
      else
        signup_enterprise_path(with: @benefit)
      end
    end
  end
end
