# typed: true
# frozen_string_literal: true

module Compare
  class CommitsListComponent < ApplicationComponent
    include ResilienceHelper
    include DiffViewHelper
    include HydroHelper

    attr_reader :comparison, :current_user, :commits, :current_page

    def initialize(comparison:, page:, current_user:)
      @comparison = comparison
      @current_user = current_user
      @current_page = [page.to_i, 1].max

      preload_commits
    end

    memoize def grouped_commits
      grouped_commits_by_zone(commits)
    end

    def grouped_commits_by_zone(commits)
      zone = current_user&.time_zone || Time.zone
      commits.group_by do |commit|
        commit.committed_date.in_time_zone(zone).to_date
      end.sort
    end

    memoize def comment_counts_by_oid
      with_database_error_fallback(fallback: Hash.new(0)) do
        comparison.repo.commit_comments.where(commit_id: commits.map(&:oid)).group(:commit_id).count
      end
    end

    def preload_commits
      commits = comparison.paginated_commits(page: current_page)

      Promise.all(
        commits.map do |commit|
          [
            commit.author_actors.map { |git_actor| [git_actor.async_visible_actor(current_user), git_actor.async_commits_path_uri] },
            commit.committer_actor.async_visible_actor(current_user),
            commit.committer_actor.async_commits_path_uri,
            commit.async_authored_by_committer?,
            commit.async_short_message_html,
            with_async_database_error_fallback(
              commit.async_has_status_check_rollup?,
              fallback: false
            ),
            commit.async_unique_visible_author_actors(current_user).then { |authors| authors.map { |author| author.async_visible_user(current_user) } },
         ].flatten
        end.flatten
      ).sync

      @commits = commits
    end

    def current_range
      "#{comparison.base}...#{comparison.head}"
    end

    def has_pagination?
      comparison.rev_list.count > GitHub::Comparison::COMPARE_PER_PAGE_DEFAULT * current_page
    end

    def load_more_path
      compare_commit_list_path(user_id: comparison.repo.owner, repository: comparison.repo.to_s, range: current_range)
    end

    def click_tracking_attributes
      payload = {
        user_id: current_user&.id,
        repository_id: comparison.base_repo&.id,
        category: "compare_show",
        data: comparison.click_tracking_attributes,
        action: "load_more_commits"
      }
      hydro_click_tracking_attributes("pull_request.user_action", payload)
    end
  end
end
