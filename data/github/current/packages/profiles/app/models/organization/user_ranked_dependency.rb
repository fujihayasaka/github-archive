# typed: true
# frozen_string_literal: true

module Organization::UserRankedDependency
  extend ActiveSupport::Concern

  include UserRanked::Scope

  COMMIT_RECENCY_WINDOW = 6.months

  class_methods do
    # Return ranked organizations for the given user
    def compute_ranked_ids(user:)
      # Orgs the user has added to their profile bio
      user.async_verified_company_organizations.then do |orgs|
        bio_org_ids = orgs.pluck(:id)

        # Orgs the user has committed the most to in the past COMMIT_RECENCY_WINDOW
        most_committed_org_ids = []
        unless user.large_scale_contributor?
          repo_commit_counts = CommitContributions.domain.days_with_commits_count_by_repo(user: user, since: COMMIT_RECENCY_WINDOW.ago)
          repos = Repository.where(id: repo_commit_counts.keys).select(:id, :organization_id).index_by(&:id)
          org_counts = repo_commit_counts.each_with_object(Hash.new(0)) do |(repo_id, commit_count), hash|
            organization_id = repos[repo_id]&.organization_id
            hash[organization_id] += commit_count if organization_id
          end
          most_committed_org_ids = org_counts.sort_by { |_org_id, count| count }.reverse.map(&:first)
        end

        # Both in order ensuring uniqueness
        [*bio_org_ids, *most_committed_org_ids].uniq
      end.sync
    end
  end
end
