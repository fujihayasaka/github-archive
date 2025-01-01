# typed: true
# frozen_string_literal: true

module Dependabot
  class RepositoryAccess
    include Scientist
    def self.for(org:, actor:)
      new(org: org, actor: actor)
    end

    def initialize(org:, actor:)
      @organization = org
      @actor = actor
    end

    # Public: Given a collection of Git URLs that were unreachable during a
    # Dependabot update job, find the corresponding repositories (if any) that
    # are *not* yet included in the organization's Dependabot repository access
    # list. These repositories are the ones we can recommend adding to the
    # organization's Dependabot repository access list in order to allow update
    # jobs to complete successfully.
    #
    # urls - An Array of Strings representing Git URLs.
    #
    # Returns an Array of Repositories.
    def grantable_repositories_for_unreachable_dependencies(urls)
      return [] if urls.blank?

      pattern = /#{@organization.display_login}\/(?<name>[^\/]+)/

      # NOTE: We match against the github domain in review lab instead of the
      # host name (e.g. name.review-lab.github.com), otherwise match against
      # host name to maintain isolation for GHES instances hosted on different
      # sub-domains where there might be orgs and repos with the same names
      host = GitHub.dynamic_lab? ? GitHub.host_domain : GitHub.host_name
      names =
        urls
        .select { |url| url.include?(host) }
        .map do |url|
          match = url.delete_suffix(".git").match(pattern)
          match && match[:name]
        end
        .compact
      return [] if names.blank?

      remote_config = client.get_repository_access(owner_github_id: @organization.id)

      repos = @organization
        .repositories.where(name: names)
        .reject { |r| remote_config.repository_github_ids.include?(r.id) }
      return repos if @organization.adminable_by?(@actor)

      promise_array = repos.map { |repo| repo.async_pullable_by?(@actor) }

      viewable_repos = Promise.all(promise_array).then do |can_pull|
        viewable_repos_filtered = repos.select.with_index { |_repo, i| can_pull[i] }
        viewable_repos_filtered
      end.sync

      viewable_repos

    rescue Dependabot::Twirp::ServiceUnavailableError
      []
    end

    # Public: Add the given repositories to the organization's Dependabot
    # repository access list.
    def append(repository_ids:)
      return if repository_ids.blank?

      remote_config = client.get_repository_access(owner_github_id: @organization.id)

      update_repository_ids(
        repository_ids + remote_config.repository_github_ids.to_a,
      )
    end

    # Public: Remove the given repositories from the organization's Dependabot
    # repository access list.
    def remove(repository_ids:)
      return if repository_ids.blank?

      remote_config = client.get_repository_access(owner_github_id: @organization.id)

      update_repository_ids(
        remote_config.repository_github_ids.to_a - repository_ids,
      )
    end

    # Public: Sets the given repositories as the organization's Dependabot
    # repository access list, replacing the previous settings (if any).
    def update(repository_ids: nil)
      update_repository_ids(repository_ids) unless repository_ids.nil?
    end

    # Public: Returns all repositories in the organization that currently have
    # Dependabot access enabled. This reflects the organization's current
    # Dependabot repository access list.
    #
    # Returns an ActiveRecord::Relation of Repository objects.
    def list
      remote_config = client.get_repository_access(owner_github_id: @organization.id)
      @organization.repositories.where(id: remote_config.repository_github_ids.to_a)
    end

    # Internal
    def update_repository_ids(unsafe_repository_ids)
      repository_ids = @organization.repositories.where(id: unsafe_repository_ids).pluck(:id)
      if repository_ids.any?
        AutomaticAppInstallation.trigger(
          type: :dependabot_repository_access_updated,
          actor: @actor,
          originator: { target_id: @organization.id, repository_ids: repository_ids },
        )
      end

      client.set_selected_repositories(
        owner_github_id: @organization.id,
        repository_github_ids: repository_ids,
      )

      GitHub.instrument("dependabot_repository_access.repositories_updated", actor: @actor, org: @organization)
    end

    # Internal
    def client
      Dependabot::Twirp.repository_access_service_client
    end
  end
end
