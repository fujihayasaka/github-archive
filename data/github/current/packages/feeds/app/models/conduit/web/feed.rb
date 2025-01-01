# typed: true
# frozen_string_literal: true

# Conduit::Web::Feed serves as a place to encapsulate
# metadata that is directly related to rendering the visual
# feed on github.com
module Conduit
  class Web::Feed < Conduit::Feed
    include GitHub::Memoizer

    def after_build
      GitHub.dogstats.distribution_time("conduit.preload_feed", tags:) do
        preload_followed_by
        preload_sponsored_by_viewer
        preload_sponsoring_viewer
        preload_stars
        preload_release_short_description
        preload_sponsorable
        preload_pull_request_body_html
        preload_pull_request_changed_commits
        preload_sponsorable_owner
        preload_pull_request_comment_body_html
        preload_issue_body_html
        preload_issue_comment_body_html
        preload_public_repository_count
      end
      super
    end

    def preload_followed_by
      users = users_by_id.values
      GitHub::PrefillAssociations.prefill_batch_method(users, :followed_by?, viewer)
    end

    def preload_sponsored_by_viewer
      time_key = "for_you_feed.preload_sponsored_by.time"
      GitHub.dogstats.time(time_key) do
        actors = users_by_id.values
        GitHub::PrefillAssociations.prefill_batch_method(actors, :sponsored_by_viewer?, viewer)
      end
    end

    def preload_sponsoring_viewer
      time_key = "for_you_feed.preload_sponsoring_viewer.time"
      GitHub.dogstats.time(time_key) do
        actors = users_by_id.values
        GitHub::PrefillAssociations.prefill_batch_method(actors, :sponsoring_viewer?, viewer)
      end
    end

    def preload_release_short_description
      time_key = "for_you_feed.preload_release_short_description.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(
          releases_by_id.values,
          :short_description_info,
          ::Feed::Cards::ReleaseComponent::SHORT_DESCRIPTION_IMG_FILTER,
        )
      end
    end

    def preload_sponsorable
      time_key = "for_you_feed.preload_sponsorable.time"

      GitHub.dogstats.time(time_key) do
        users = users_by_id.values
        GitHub::PrefillAssociations.prefill_batch_method(users, :sponsorable?)
      end
    end

    def preload_sponsorable_owner
      time_key = "for_you_feed.preload_sponsorable_owner.time"
      GitHub.dogstats.time(time_key) do
        release_repos = items.filter_map { |item| item.release_event? && item.subject.repository }
        GitHub::PrefillAssociations.prefill_batch_method(release_repos, :sponsorable_owner?)
      end
    end

    def preload_pull_request_body_html
      time_key = "for_you_feed.preload_pull_request_body_html.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(
          pull_requests_by_id.values,
          :prelude_body_html,
          FeedCards::PullRequestViewComponentMethods::BODY_HTML_CONTEXT,
        )
      end
    end

    def preload_pull_request_comment_body_html
      time_key = "org_feed.preload_pull_request_comment_body_html.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(
          pull_request_comments_by_id.values,
          :prelude_body_html,
          FeedCards::CommentViewComponentMethods::BODY_HTML_CONTEXT,
        )
      end
    end

    def preload_issue_comment_body_html
      time_key = "org_feed.preload_issue_comment_body_html.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(
          issue_comments_by_id.values,
          :prelude_body_html,
          FeedCards::CommentViewComponentMethods::BODY_HTML_CONTEXT,
        )
      end
    end

    def preload_issue_body_html
      time_key = "for_you_feed.preload_issue_body_html.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(
          issues_by_id.values,
          :prelude_body_html,
          FeedCards::IssueViewComponentMethods::BODY_HTML_CONTEXT,
        )
      end
    end

    def preload_pull_request_changed_commits
      time_key = "for_you_feed.preload_pull_request_changed_commits.time"

      GitHub.dogstats.time(time_key) do
        GitHub::PrefillAssociations.prefill_batch_method(
          pull_requests_by_id.values,
          :prelude_changed_commits,
        )
      end
    end

    # Public: Given a list of repository IDs, return a map [repository_id: true]
    # for every repository starred by the user
    def preload_stars
      return [] if viewer.nil?

      time_key = "for_you_feed.get_starred_repository_ids.time"
      GitHub.dogstats.time(time_key) do
        repo_ids = items.filter_map { |item| item.repo_event? && item.repository.id }.uniq
        Stars.domain.precache_repos_starred_by_user?(repo_ids, viewer.id)
      end
    end

    def preload_public_repository_count
      users = users_by_id.values
      GitHub::PrefillAssociations.prefill_batch_method(users, :public_repository_count)
    end

    # Public: Fetches data about reactions for a group of discussions
    #
    # Returns a hash with discussion ID keys and hash values. The keys of the
    # nested hashes are strings describing the reaction (e.g. "smile"), and
    # the values of the nested hashes are counts of how many of those kinds of
    # of reactions exist for that release.
    memoize def reaction_count_by_content_by_discussion_id
      return if GitHub.flipper[:disable_discussion_reactions_on_dashboard_feed].enabled?(viewer)

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
      return if GitHub.flipper[:disable_discussion_reactions_on_dashboard_feed].enabled?(viewer)

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
      return if GitHub.flipper[:disable_release_reactions_on_dashboard_feed].enabled?(viewer)

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
      return if GitHub.flipper[:disable_release_reactions_on_dashboard_feed].enabled?(viewer)

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

    # Public: Fetches data about reactions by a viewer to a group of feed posts.
    #
    # Returns a hash with release ID keys and array values. The array values
    # contain strings representing the reactions (e.g. "smile") that the viewer
    # had for that feed post comment.
    memoize def viewer_reaction_contents_by_feed_post_id
      return [] if GitHub.flipper[:disable_feed_post_reactions_on_dashboard_feed].enabled?(viewer)

      time_key = "for_you_feed.get_reaction_contents_feed_post.time"
      GitHub.dogstats.time(time_key) do
        Reaction.
          where(subject_type: "FeedPost", subject_id: feed_post_ids, user: viewer).
          pluck(:subject_id, :content).
          each_with_object({}) do |(feed_post_id, content), result|
            result[feed_post_id] ||= []
            result[feed_post_id].push(content)
          end
      end
    end

    # Public: Fetches data about reactions by a viewer to a group of feed post comments.
    #
    # Returns a hash with release ID keys and array values. The array values
    # contain strings representing the reactions (e.g. "smile") that the viewer
    # had for that release.
    memoize def viewer_reaction_contents_by_feed_post_comment_id
      context = FeedPost::CommentReactionContext.new(comment_ids: feed_post_comment_ids, viewer: viewer)
      context.viewer_reaction_contents_by_feed_post_comment_id
    end


    def pull_request_issue_ids
      @pull_request_issue_ids ||= pull_requests_by_id.values.map { |pr| pr.issue.id }
    end


    # Public: Fetches data about reactions for a group of pull requests
    #
    # Returns a hash with pull request ID keys and hash values. The keys of the
    # nested hashes are strings describing the reaction (e.g. "smile"), and
    # the values of the nested hashes are counts of how many of those kinds of
    # of reactions exist for that pull request issue.
    memoize def reaction_count_by_content_by_pr_issue_id
      return if GitHub.flipper[:disable_pull_request_reactions_on_dashboard_feed].enabled?(viewer)

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
      return if GitHub.flipper[:disable_pull_request_reactions_on_dashboard_feed].enabled?(viewer)

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
