# typed: true
# frozen_string_literal: true

# Conduit::Web::Feed serves as a place to encapsulate
# metadata that is directly related to rendering the visual
# feed on github.com
module Conduit
  class Web::Feed < Conduit::Feed
    include GitHub::Memoizer

    def after_build
      preload_followed_by
      preload_sponsored_by_viewer
      preload_sponsoring_viewer
      preload_stars
      preload_release_short_description
      preload_sponsorable
      preload_all_body_html
      preload_pull_request_changed_commits
      preload_sponsorable_owner
      preload_public_repository_count
      super
    end

    def preload_followed_by
      users = users_by_id.values
      return if users.empty?
      GitHub::PrefillAssociations.prefill_batch_method(users, :followed_by?, viewer)
    end

    def preload_sponsored_by_viewer
      actors = users_by_id.values
      return if actors.empty?
      time_key = "for_you_feed.preload_sponsored_by.time"
      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(actors, :sponsored_by_viewer?, viewer)
      end
    end

    def preload_sponsoring_viewer
      actors = users_by_id.values
      return if actors.empty?
      time_key = "for_you_feed.preload_sponsoring_viewer.time"
      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(actors, :sponsoring_viewer?, viewer)
      end
    end

    def preload_release_short_description
      releases = releases_by_id.values
      return if releases.empty?
      time_key = "for_you_feed.preload_release_short_description.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(
          releases,
          :short_description_info,
          ::Feed::Cards::ReleaseComponent::SHORT_DESCRIPTION_IMG_FILTER,
        )
      end
    end

    def preload_sponsorable
      users = users_by_id.values
      return if users.empty?
      time_key = "for_you_feed.preload_sponsorable.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(users, :sponsorable?)
      end
    end

    def preload_sponsorable_owner
      release_repos = items.filter_map { |item| item.release_event? && item.subject.repository }
      return if release_repos.empty?
      time_key = "for_you_feed.preload_sponsorable_owner.time"
      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(release_repos, :sponsorable_owner?)
      end
    end

    # Fires async_body_html for all 4 content types (PR issues, issues, PR comments,
    # issue comments) in a single Promise.all / .sync instead of 4 sequential .sync calls.
    # PullRequests delegate body_html to their underlying Issue, so we operate on
    # those Issue objects directly.
    def preload_all_body_html
      pr_issues = pull_requests_by_id.values.filter_map(&:issue)

      records = [
        *pr_issues,
        *issues_by_id.values,
        *pull_request_comments_by_id.values,
        *issue_comments_by_id.values,
      ].reject { |record| record.instance_variable_defined?(:@body_html) }

      return if records.empty?

      time_key = "for_you_feed.preload_all_body_html.time"
      GitHub.dogstats.time(time_key) do
        Promise.all( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          records.map do |record|
            record.async_body_html(context: {}).then do |html|
              record.preload_attr(:body_html, html)
            end
          end
        ).sync
      end
    end

    def preload_pull_request_changed_commits
      pull_requests = pull_requests_by_id.values
      return if pull_requests.empty?
      time_key = "for_you_feed.preload_pull_request_changed_commits.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(
          pull_requests,
          :prelude_changed_commits,
        )
      end
    end

    # Public: Given a list of repository IDs, return a map [repository_id: true]
    # for every repository starred by the user
    def preload_stars
      return [] if viewer.nil?

      repo_ids = items.filter_map { |item| item.repo_event? && item.repository.id }.uniq
      return if repo_ids.empty?

      time_key = "for_you_feed.get_starred_repository_ids.time"
      GitHub.dogstats.time(time_key) do
        Stars.domain.precache_repos_starred_by_user?(repo_ids, viewer.id)
      end
    end

    def preload_public_repository_count
      users = users_by_id.values
      return if users.empty?
      GitHub::PrefillAssociations.prefill_batch_method(users, :public_repository_count)
    end

    # Public: Fetches data about reactions for a group of discussions
    #
    # Returns a hash with discussion ID keys and hash values. The keys of the
    # nested hashes are strings describing the reaction (e.g. "smile"), and
    # the values of the nested hashes are counts of how many of those kinds of
    # of reactions exist for that release.
    memoize def reaction_count_by_content_by_discussion_id
      time_key = "for_you_feed.get_reaction_count_discussion.time"
      GitHub.dogstats.time(time_key) do
        DiscussionReaction.
          reaction_count_by_content_by_discussion_id(discussion_ids: discussion_ids)
      end
    end

    # Public: Fetches data about reactions by a viewer to a group of discussions.
    #
    # Returns a hash with discussion ID keys and array values. The array values
    # contain strings representing the reactions (e.g. "smile") that the viewer
    # had for that release.
    memoize def viewer_reaction_contents_by_discussion_id
      time_key = "for_you_feed.get_reaction_contents_discussion.time"
      GitHub.dogstats.time(time_key) do
        DiscussionReaction.
          viewer_reaction_contents_by_discussion_id(
            viewer: viewer,
            discussion_ids: discussion_ids
          )
      end
    end

    # Public: Fetches data about reactions for a group of releases
    #
    # Returns a hash with release ID keys and hash values. The keys of the
    # nested hashes are strings describing the reaction (e.g. "smile"), and
    # the values of the nested hashes are counts of how many of those kinds of
    # of reactions exist for that release.
    memoize def reaction_count_by_content_by_release_id
      time_key = "for_you_feed.get_reaction_count_release.time"
      GitHub.dogstats.time(time_key) do
        Reaction.
          where(subject_type: "Release", subject_id: release_ids).
          group(:subject_id, :content).
          count.
          each_with_object({}) do |((release_id, content), reaction_count), result|
            result[release_id] ||= {}
            result[release_id][content] = reaction_count
          end
      end
    end

    # Public: Fetches data about reactions by a viewer to a group of releases.
    #
    # Returns a hash with release ID keys and array values. The array values
    # contain strings representing the reactions (e.g. "smile") that the viewer
    # had for that release.
    memoize def viewer_reaction_contents_by_release_id
      time_key = "for_you_feed.get_reaction_contents_release.time"
      GitHub.dogstats.time(time_key) do
        Reaction.
          where(subject_type: "Release", subject_id: release_ids, user: viewer).
          pluck(:subject_id, :content).
          each_with_object({}) do |(release_id, content), result|
            result[release_id] ||= []
            result[release_id].push(content)
          end
      end
    end

    memoize def pull_request_issue_ids
      pull_requests_by_id.values.map { |pr| pr.issue.id }
    end

    # Public: Fetches data about reactions for a group of pull requests
    #
    # Returns a hash with pull request ID keys and hash values. The keys of the
    # nested hashes are strings describing the reaction (e.g. "smile"), and
    # the values of the nested hashes are counts of how many of those kinds of
    # of reactions exist for that pull request issue.
    memoize def reaction_count_by_content_by_pr_issue_id
      time_key = "for_you_feed.get_reaction_count_pull_request.time"
      @pull_request_reaction_count = GitHub.dogstats.time(time_key) do
        reaction_query = IssueReaction.
            where(issue_id: pull_request_issue_ids).
            group(:issue_id, :content)

        reaction_query.
        count.
        each_with_object({}) do |((issue_id, content), reaction_count), result|
          result[issue_id] ||= {}
          result[issue_id][content] = reaction_count
        end
      end
    end

    # Public: Fetches data about reactions by a viewer to a group of pull requests.
    #
    # Returns a hash with pull request ID keys and array values. The array values
    # contain strings representing the reactions (e.g. "smile") that the viewer
    # had for that pull request issue.
    def viewer_reaction_contents_by_pr_issue_id
      return @pull_request_reaction_contents if defined?(@pull_request_reaction_contents)

      time_key = "for_you_feed.get_reaction_contents_pull_request.time"
      @pull_request_reaction_contents = GitHub.dogstats.time(time_key) do
        reaction_query = IssueReaction.
            where(issue_id: pull_request_issue_ids, user: viewer).
            pluck(:issue_id, :content)

        reaction_query.
          each_with_object({}) do |(issue_id, content), result|
            result[issue_id] ||= []
            result[issue_id].push(content)
          end
      end
    end

    # Public: Fetches data about reactions for a group of issues
    #
    # Returns a hash with issue ID keys and hash values. The keys of the
    # nested hashes are strings describing the reaction (e.g. "smile"), and
    # the values of the nested hashes are counts of how many of those kinds of
    # of reactions exist for that issue.
    memoize def reaction_count_by_content_by_issue_id
      time_key = "for_you_feed.get_reaction_count_issue.time"
      @issue_reaction_count = GitHub.dogstats.time(time_key) do
        reaction_query = IssueReaction.
            where(issue_id: issue_ids).
            group(:issue_id, :content)

        reaction_query.
        count.
        each_with_object({}) do |((issue_id, content), reaction_count), result|
          result[issue_id] ||= {}
          result[issue_id][content] = reaction_count
        end
      end
    end

    # Public: Fetches data about reactions by a viewer to a group of issues.
    #
    # Returns a hash with issue ID keys and array values. The array values
    # contain strings representing the reactions (e.g. "smile") that the viewer
    # had for that issue.
    def viewer_reaction_contents_by_issue_id
      return @issue_reaction_contents if defined?(@issue_reaction_contents)

      time_key = "for_you_feed.get_reaction_contents_issue.time"
      @issue_reaction_contents = GitHub.dogstats.time(time_key) do
        reaction_query = IssueReaction.
            where(issue_id: issue_ids, user: viewer).
            pluck(:issue_id, :content)

        reaction_query.
          each_with_object({}) do |(issue_id, content), result|
            result[issue_id] ||= []
            result[issue_id].push(content)
          end
      end
    end

    def tags
      super.concat(["feed_type:web"])
    end
  end
end
