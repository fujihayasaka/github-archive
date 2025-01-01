# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module GitHub
  module Config
    module CommitContributions
      # Whether commit contribution data should be stored in CommitContributionSummary
      # tables in addition to or instead of CommitContribution tables.
      #
      # This is currently enabled in the dotcom environment only, because the full
      # CommitContribution history is too large in that environment.
      sig { returns(T::Boolean) }
      def commit_contribution_summaries_enabled?
        !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
      end
    end
  end

  extend Config::CommitContributions
end
