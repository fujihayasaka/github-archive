# typed: true
# frozen_string_literal: true

module DependencyGraph
  class UpdateGraphJobComponent < ApplicationComponent
    attr_reader :owner, :repository, :update_jobs, :update_job, :dependabot_error, :dependabot_unavailable

    def initialize(owner:, repository:, update_jobs:, dependabot_error:, dependabot_unavailable:)
      @owner = owner
      @repository = repository
      @update_jobs = update_jobs
      @dependabot_error = dependabot_error
      @dependabot_unavailable = dependabot_unavailable

      # The most relevant job is the one with errors, or warnings, and the latest one
      @update_job = update_jobs.max_by do |job|
        [
          if job.errors&.any?
            2 # Highest priority
          elsif job.warnings&.any?
            1 # Medium priority
          else
            0
          end,
          job.finished_at&.to_i || -Float::INFINITY # Latest job
        ]
      end
    end

    def body
      if access_recommendation?
        helpers.github_simplified_markdown(access_recommendation_body)
      elsif update_job_error?
        helpers.github_simplified_markdown(
          "#{update_job.last_error.details}"
        )
      else
        ""
      end
    end

    def broken?
      update_job&.state == :NO_SUCCESSFUL_RUNS
    end

    def update_job_error?
      update_job&.last_error.present? || access_recommendation?
    end

    def update_job_warnings?
      update_job&.warnings&.any?
    end

    memoize def grantable_repositories
      Dependabot::RepositoryAccess.for(org: owner, actor: current_user).
                                  grantable_repositories_for_unreachable_dependencies(update_job&.unreachable_git_dependency_urls)
    end

    memoize def adminable_by_current_user?
      owner.adminable_by?(current_user)
    end

    memoize def access_recommendation?
      return false unless update_job&.access_recommendation_error?
      return false unless owner.organization?
      return false unless update_job&.ecosystem_supports_repository_access?

      grantable_repositories.any?
    end

    def failed_update_jobs_link
      base = actions_workflows_menu_path(owner, repository) + "/dependabot/update-graph"
      encoded_ids = failing_job_ids.map do |id|
        URI.encode_www_form_component("##{id}")
      end
      encoded_query = "is%3Afailure+#{encoded_ids.join("+OR+")}"
      "#{base}?query=#{encoded_query}"
    end

    def errors_count
      "#{update_jobs.size} #{'error'.pluralize(update_jobs.size)}"
    end

    # A user must be a repository admin or security manager to refresh dependency data.
    # The refresh route is only available when the dependency graph is enabled (not on Enterprise).
    def show_refresh_link?
      GitHub.dependency_graph_enabled? &&
        SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_repo_security_products?
    end

    def refresh_on_cooldown?
      data_refresh_manager.on_cooldown?
    end

    def cooldown_ends_at
      data_refresh_manager.cooldown_ends_at
    end

    def refresh_graph_path
      Rails.application.routes.url_helpers.refresh_dependency_graph_path(owner, repository)
    end

    private

    def failing_job_ids
      update_jobs.filter_map do |job|
        job.id if job.errors&.any?
      end
    end

    def access_recommendation_body
      if adminable_by_current_user?
        admin_access_recommendation_body
      else
        non_admin_recommendation_body
      end
    end

    def admin_access_recommendation_body
      nwo = grantable_repositories.first.name_with_display_owner

      if grantable_repositories.one?
        <<~BODY
            You can fix the issue by granting Dependabot access, which will enable any repository in @#{owner.display_login} to include #{nwo} in graph updates. Be sure that you want to share #{nwo} with everyone in your organization.

            If you don't need a private dependency from #{nwo}, remove it from your repository's manifest file.
        BODY
      else
        <<~BODY
            You can fix the issue by granting Dependabot access, which will enable any repository in @#{owner.display_login} to include the repositories listed above in graph updates.
            Be sure that you want to share those repositories with everyone in your organization.

            If you don't need a private dependency from #{nwo}, remove it from your repository's manifest file.
        BODY
      end
    end

    def non_admin_recommendation_body
      this_page_link = helpers.network_dependabot_show_path(owner, repository, update_job)
      org_owner_link = helpers.org_people_path(owner, query: "role:owner")
      if grantable_repositories.one?
        <<~BODY
            Contact your [organization owner](#{org_owner_link}) and ask them to grant Dependabot access to #{grantable_repositories.first.name_with_display_owner}.

            They can grant access by coming to [this page](#{this_page_link}), where we’ll guide them through the process.
        BODY
      else
        <<~BODY
            Contact your [organization owner](#{org_owner_link}) and ask them to grant Dependabot access to the repositories listed above.
        BODY
      end
    end

    memoize def data_refresh_manager
      DependencyGraph::DataRefreshManager.new(repository)
    end
  end
end
