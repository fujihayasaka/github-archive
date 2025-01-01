# typed: true
# frozen_string_literal: true

# In the event that there is a repository that hosts unsavory or
# unsafe content, stafftools is able to revoke certain privileges
# in order to minimize the amount of exposure the repository gets.

class Stafftools::NetworkPrivilege < ApplicationRecord::Domain::Repositories
  include Instrumentation::Model

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain class_name: "::Repository"

  scope :requires_login_or_collaborators_only, -> {
    where("network_privileges.require_login = ? OR " +
          "network_privileges.collaborators_only = ?", true, true)
  }

  scope :hidden_from_discovery, -> { where(hide_from_discovery: true) }

  # Queue jobs to recalculate trending repositories.
  # Should be done after hiding a repository from discovery.
  # If a batch of repositories have been hidden (e.g. a network), only one call to
  # `recalculate_trending_repos` should be made.
  # Multiple calls are redundant and expensive.
  def self.recalculate_trending_repos
    return if GitHub.flipper[:skip_trending_repo_recalculation].enabled?

    %w[daily weekly monthly].each do |period|
      CalculateTrendingReposJob.perform_later(period)
    end
  end
end
