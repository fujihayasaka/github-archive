# typed: true
# frozen_string_literal: true

module Signup
  class SelectAccountListItemComponent < ApplicationComponent
    include WithParameterValidation


    attr_reader :account, :benefit

    sig { params(account: T.any(Organization, Business), benefit: T.nilable(String)).void }
    def initialize(account:, benefit: nil)
      @account = account
      @benefit = benefit
    end


    memoize def account_type
      if @account.is_a?(Organization)
        "org"
      else
        "business"
      end
    end

    private

    sig { returns(T::Boolean) }
    def render?
      return false if GitHub.single_business_environment?
      true
    end

    def button_path
      if @account.is_a?(Business) && FeatureFlag.vexi.enabled?(:get_started_create_business_intent, @account, default: false)
        return create_business_intent_path(with: @benefit, account: @account, type: account_type)
      end
      benefit_path(@benefit, @account)
    end
  end
end
