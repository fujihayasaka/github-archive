# typed: true
# frozen_string_literal: true

module PullRequest::FindersDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PullRequest }

  included do
    T.bind(self, T.class_of(PullRequest))
    # Public: Filter to include only open PullRequests
    #
    # Examples
    #
    #   PullRequest.open.all
    #   # => [ <...list of open PullRequest objects ...> ]
    #
    # This is a named scope.
    scope :open_pulls, -> {
      includes(:issue)
      .where(issues: { state: "open" })
    }

    scope :open_pull_requests, -> {
      open_pulls.where("issues.repository_id = pull_requests.repository_id")
    }

    scope :open_pull_requests_by_status, -> {
      includes(:issue)
      .where(status: "open")
    }

    # Public: Filter to include only draft PullRequests
    scope :drafts, -> { where(work_in_progress: true) }

    # Public: Filter to include only closed PullRequests
    #
    # Examples
    #
    #   PullRequest.closed.all
    #   # => [ <...list of closed PullRequest objects ...> ]
    #
    # This is a named scope.
    scope :closed_pulls, -> { includes(:issue).where(issues: { state: "closed" }) }

    # Public: Filter PullRequests by head repository and ref.
    #
    # repo - Repository instance for the head repository
    # ref  - Head ref for the pull request
    #
    # Examples
    #
    #   PullRequest.for_head_repo_and_head_ref(@repo, "new-feature").all
    #   # => [ <...list of PullRequest objects from the repo with the head ref ...> ]
    #
    # This is a named scope.
    scope :for_head_repo_and_head_ref, -> (repo, ref) {
      where(head_repository: repo, head_ref: Git::Ref.safe_ref_name(ref_names: ref))
    }

    scope :for_base_repo_and_base_ref, -> (repo, ref) {
      where(base_repository: repo, base_ref: Git::Ref.safe_ref_name(ref_names: ref))
    }
    # Public: Filter PullRequests by base ref and base repo.
    #
    # repo - Repository instance for the base repository
    # ref  - Base ref for the pull request
    #
    # Examples
    #
    #   PullRequest.for_base_ref("develop").all
    #   # => [ <...list of PullRequest objects with the given base ref ...> ]
    #
    # This is a named scope.
    scope :for_base_ref, -> (ref) {
      where(base_ref: Git::Ref.safe_ref_name(ref_names: ref))
    }

    # Public: Filter and order PullRequests by creation timestamp.
    #
    # direction - Optional direction for sort ('asc' or 'desc'), defaults to 'asc'
    #
    # Examples
    #
    #   PullRequest.by_creation.all
    #   # => [ <...list of PullRequest objects, ordered by decreasing creation timestamp...> ]
    #
    #   PullRequest.by_creation('asc').all
    #   # => [ <...list of PullRequest objects, ordered by increasing creation timestamp...> ]
    #
    # This is a named scope.
    scope :by_creation, -> (*direction) {
      which = direction.empty? ? "asc" : direction.first
      order("pull_requests.created_at" => (which == "asc" ? :asc : :desc))
    }

    # Public: Filter and order PullRequests by update timestamp.
    #
    # direction - Optional direction for sort ('asc' or 'desc'), defaults to 'asc'
    #
    # Examples
    #
    #   PullRequest.by_updates.all
    #   # => [ <...list of PullRequest objects, ordered by decreasing update timestamp...> ]
    #
    #   PullRequest.by_updates('asc').all
    #   # => [ <...list of PullRequest objects, ordered by increasing update timestamp...> ]
    #
    # This is a named scope.
    scope :by_updates, -> (*direction) {
      which = direction.empty? ? "asc" : direction.first
      order("pull_requests.updated_at" => (which == "asc" ? :asc : :desc))
    }

    scope :sorted_by, lambda { |field, direction|
      case field
      when "updated"
        by_updates(direction)
      when "popularity"
        GitHub.dogstats.increment("pull_request.sorted_by_popularity")
        by_popularity(direction)
      when "long-running", "longevity"
        by_longevity(direction)
      else
        # default is descending order by creation
        by_creation(direction)
      end
    }
  end

  class_methods do
    # Public: Filter and order PullRequests by popularity, which is the number of
    # comments made on the issue associated with the PullRequest.
    #
    # direction - Optional direction for sort ('asc' or 'desc'), defaults to 'asc'
    #
    # Examples
    #
    #   PullRequest.by_popularity.all
    #   # => [ <...list of PullRequest objects, ordered by decreasing popularity...> ]
    #
    #   PullRequest.by_popularity('asc').all
    #   # => [ <...list of PullRequest objects, ordered by increasing popularity...> ]
    #
    # Note: this method returns an activerecord relation, however the resulting relation
    # is not chainable with all scopes. This due to the additional column in the select
    # statement, which is required for Vitess compatibility.
    def by_popularity(*direction)
      which = direction.empty? ? "asc" : direction.first

      T.unsafe(self).joins(:issue)
        .select(Arel.sql("pull_requests.*"), Arel.sql("issues.issue_comments_count"))
        .order("issues.issue_comments_count" => (which == "asc" ? :asc : :desc))
    end

    # Public: Filter and order PullRequests by longevity.  Longevity is the duration
    # between creation and last update.
    #
    # direction - Optional direction for sort ('asc' or 'desc'), defaults to 'asc'
    #
    # Examples
    #
    #   PullRequest.by_longevity.all
    #   # => [ <...list of PullRequest objects, ordered by decreasing longevity...> ]
    #
    #   PullRequest.by_longevity('asc').all
    #   # => [ <...list of PullRequest objects, ordered by increasing longevity...> ]
    #
    # Note: this method returns an activerecord relation, however the resulting relation
    # is not chainable with all scopes. This due to the additional column in the select
    # statement, which is required for Vitess compatibility.
    def by_longevity(*direction)
      which = direction.empty? ? "asc" : direction.first

      T.unsafe(self).order(Arel.sql("DATEDIFF(pull_requests.updated_at, pull_requests.created_at)") => (which == "asc" ? :asc : :desc))
    end

    # Public: return a list of filtered and ordered PullRequests matching the passed
    # option criteria.
    #
    # options - optional hash of parameters which will specify how the PullRequests are
    #           to be ordered and filtered (default: {}):
    #           :sort      - which sorting type to use (optional); valid values include
    #                        'created', 'updated', 'popularity', and 'long-running'; if
    #                        no :sort value is specified, 'created' is assumed, with a
    #                        :direction value of 'desc'
    #           :direction - should results be ordered in ascending or descending
    #                        order? (optional)  Valid values are 'asc' and 'desc',
    #                        defaults to 'asc'.
    #           :state     - Scope to 'open' or 'closed' state. (defaults to nil)
    #           :exclude   - Comma-separated list of PullRequest issue states to
    #                        exclude, defaults to 'closed'.
    #
    # Examples
    #
    #   PullRequest.filtered_and_ordered
    #   # => [ <...list of PullRequest objects ...> ]
    #
    #   PullRequest.filtered_and_ordered(:sort => 'long-running', 'direction' => 'asc')
    #   # => [ <...list of PullRequest objects ...> ]
    #
    #   PullRequest.filtered_and_ordered(:state => 'open')
    #   # => [ <...list of PullRequest objects ...> ]
    def filtered_and_ordered(options = {})
      if (sort = options[:sort]).blank?
        sort = "created"
        direction = options[:direction] || "desc"
      end

      direction ||= options[:direction] || "asc"

      status =
        case options[:state]
        when /close/
          ["closed"]
        when "all"
          %w[open closed]
        else
          ["open"]
        end

      pulls = T.unsafe(self).scoped
      pulls = pulls.where(status:)
      pulls = pulls.sorted_by(sort, direction)
    end

    # Retrieve statuses and set for each pull request
    def attach_statuses(repo, pulls, with_check_runs: false, current_user: nil)
      statuses = PullRequest::MergeStatus.merge_statuses_for_pulls(repo, pulls, with_check_runs: with_check_runs, current_user: current_user)
      pulls.each do |pull|
        pull_status = statuses[pull.head_sha]
        next unless pull_status
        pull.combined_status = pull_status
      end
    end

    # Returns a Pull Request by number and repository, or nil if none found
    #
    # Options currently just supports :include to do eager loading (only the :issue
    # is eager loaded by default)
    def with_number_and_repo(number, repo, options = {})
      includes = options[:include] || :issue
      T.unsafe(self).includes(includes).
        joins(:issue).
        readonly(false). # :joins would cause the returned record to be readonly w/o this
        where("issues.repository_id = ? and issues.number = ?", repo.id, number).
        order("issues.pull_request_id ASC"). # explicitly order by issues attribute to avoid temporary table
        first # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end
end
