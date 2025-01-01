# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class ReposView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      PER_PAGE = 100 # how many repositories to show per page

      # The user in question for a list of repositories
      attr_reader :user

      # An optional page, if paginating. Define this when initializing the view.
      def page
        @page ||= 1
      end
      attr_initializable :page

      def page_title
        "#{user.login} - Repositories"
      end

      def repos?
        repos.size > 0
      end

      def repos
        @repos ||= repos_of_interest.paginate(page: page, per_page: PER_PAGE)
      end

      def contributing_repos
        user.ranked_contributed_repositories.first(10)
      end

      def commit_contributions_for(repo)
        contributions_for(Contribution::CreatedCommit, repository_id: repo.id)
      end

      def pull_request_contributions_for(repo)
        contributions_for(Contribution::CreatedPullRequest, repository_id: repo.id)
      end

      def issue_contributions_for(repo)
        contributions_for(Contribution::CreatedIssue, repository_id: repo.id)
      end

      def visibility(repo)
        repo.visibility
      end

      def plan_usage
        if GitHub.billing_enabled?
          used = user.private_repo_count_for_limit_check
          " – #{used} of #{user.plan.repos}"
        end
      end

      def span_symbol(repo)
        repo.public? ? "repo" : "lock"
      end

      def no_repos_message
        "This user does not own any repositories."
      end

      def no_contributing_repos_message
        "This user has no repository contributions."
      end

      def disk_use_classes(repo)
        "alert" if repo.disk_usage > (1000 * 1000) # 1GB
      end

      def route_classes(repo)
        if fs_offline? repo.safe_route
          "route alert"
        else
          "route"
        end
      end

      def anonymous_git_access_enabled_for_repo?(repo)
        return false unless repo.anonymous_git_access_available?

        anonymous_access_repos.include?(repo)
      end

      private

      def contributions_collector
        return @contributions_collector if @contributions_collector

        contribution_classes = [
          Contribution::CreatedCommit,
          Contribution::CreatedIssue,
          Contribution::CreatedPullRequest,
        ]
        @contributions_collector = Contribution::Collector.new(
          user: user,
          time_range: 1.year.ago..Time.zone.now,
          contribution_classes: contribution_classes,
          viewer: user,
        )
      end

      def contributions_for(contribution_class, repository_id:)
        contributions = contributions_collector.visible_contributions_of(contribution_class)
        contributions.select { |contribution| contribution.repository_id == repository_id }
      end

      # Subclass this to override what repositories are rendered for this view.
      #
      # This should return a sorted scope rather than an array when pagination
      # is enabled.
      def repos_of_interest
        if user.organization?
          user.repositories
            .private_not_internal_scope
            .includes([:network, :page, :parent])
            .order(:name)
            .network_roots
        else
          user.private_repositories
            .includes([:network, :page, :parent])
            .order(:name)
            .network_roots
        end
      end

      def fs_offline?(fs)
        return false if GitHub.enterprise?
        offline_fileservers.include? fs
      end

      def offline_fileservers
        return @offline_fileservers if defined? @offline_fileservers
        @offline_fileservers = GitHub::Stats::Site.dead_storage_servers
      end

      def anonymous_access_repos
        @anonymous_access_repos ||= repos.with_anonymous_git_access
      end
    end
  end
end
