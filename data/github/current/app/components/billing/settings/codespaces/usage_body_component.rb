# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Codespaces
      class UsageBodyComponent < ApplicationComponent
        include GitHub::Memoizer

        attr_reader :codespaces_usage, :account, :show_spending, :spending_limit_path

        def initialize(
          account:,
          show_spending: false,
          spending_limit_path: ""
        )
          @account = account
          @show_spending = show_spending
          @spending_limit_path = spending_limit_path

          query_codespace_usage
        end

        def has_codespaces_usage?
          # A call to usages will attempt to get raw usage quantities from the get_usage_breakdown
          # endpoint. This request is memoized so it will only be called once. We want to see if
          # it fails early.
          codespaces_usage.usages
          !codespaces_usage.usage_checker.request_error?
        rescue ::Billing::Api::ClientWrapper::BillingClientError
          false
        end

        def show_projected_usage?
          account.feature_enabled?(:codespaces_salus_projected_usage) && account.organization? && !codespaces_usage.projected_usage.nil?
        end

        private

        def query_codespace_usage
          @codespaces_usage = ::Billing::CodespacesUsage.new(account: account)
        end
      end
    end
  end
end
