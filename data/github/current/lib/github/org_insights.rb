# typed: true
# frozen_string_literal: true

module GitHub
  module OrgInsights
    autoload :Backfill, "github/org_insights/backfill"
    autoload :BucketedBy, "github/org_insights/bucketed_by"
    autoload :ForRepoOwner, "github/org_insights/for_repo_owner"
    autoload :InsightsData, "github/org_insights/insights_data"
    autoload :Metric, "github/org_insights/metric"
  end
end
