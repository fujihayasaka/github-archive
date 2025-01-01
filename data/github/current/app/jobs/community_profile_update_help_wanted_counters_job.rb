# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CommunityProfileUpdateHelpWantedCountersJob < ApplicationJob
  # reusing the queue created by RepositorySetCommunityHealthFlagsJob,
  # which is now deprecated. This queue can be renamed if needed
  queue_as :detect_community_health_files
  retry_on_dirty_exit

  def perform(repository_id)
    # rubocop:todo GitHub/AvoidCast
    repo = T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository))
    # rubocop:enable GitHub/AvoidCast
    return unless repo

    repo.build_community_profile if repo.community_profile.nil?
    help_wanted_label = repo.help_wanted_label
    good_first_issue_label = repo.good_first_issue_label
    community_profile = T.must(repo.community_profile)

    community_profile.help_wanted_issues_count = if help_wanted_label
      help_wanted_label.issues.open_issues.without_pull_requests.count
    else
      0
    end

    community_profile.good_first_issue_issues_count = if good_first_issue_label
      good_first_issue_label.issues.open_issues.without_pull_requests.count
    else
      0
    end

    with_write do
      community_profile.save
      repo.touch # trigger repo search indexer
    end
  end
end
