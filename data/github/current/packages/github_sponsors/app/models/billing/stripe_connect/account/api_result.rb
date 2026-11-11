# typed: true
# frozen_string_literal: true

module Billing
  module StripeConnect
    class Account
      class APIResult
        attr_reader :account, :success, :result, :error
        alias_method :success?, :success

        # account - The Billing::StripeConnect::Account that the data was being fetched for.
        # success - A Boolean indicating if the API request succeeded.
        # result - The result from the API request.
        # error - The exception that was raised when the API request failed.
        def initialize(account:, success:, result:, error:)
          @account = account
          @success = success
          @result  = result
          @error   = error
        end

        def self.success(account:, result:)
          new(
            account: account,
            success: true,
            result: result,
            error: nil,
          )
        end

        def self.failure(account:, error:)
          new(
            account: account,
            success: false,
            result: nil,
            error: error,
          )
        end
      end
    end
  end
end
