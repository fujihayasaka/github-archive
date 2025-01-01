# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Codespaces
      class ProjectedUsageComponent < ApplicationComponent
        attr_reader :account, :codespaces_usage

        def initialize(account:, codespaces_usage:)
          @account = account
          @codespaces_usage = codespaces_usage
        end

        def projected_usage
          codespaces_usage.projected_usage
        end

        def docs_url
          "#{GitHub.help_url}/billing/managing-billing-for-github-codespaces/about-billing-for-github-codespaces#viewing-projected-usage-for-an-organization"
        end
      end
    end
  end
end
