# typed: true
# frozen_string_literal: true

module Conduit
  class Feed
    include GitHub::SimplePagination
    include GitHub::Memoizer

    PER_PAGE = 20.freeze

    FOR_YOU_CONTEXT = :for_you
    PROFILE_ACTIVITY_CONTEXT = :profile_activity
    ORG_CONTEXT = :org
    LIST_CONTEXT = :list
    API_CONTEXT = :api
    ERROR = :error

    attr_reader :items, :request_id, :viewer, :twirp_items, :ranking_model_id
    attr_accessor :cached_records

    attr_reader :paginator
    private :paginator
    delegate :has_more?, :next_page, :previous_page, to: :paginator

    attr_reader :exp_context
    private :exp_context
    delegate :assignment_context, :variants, :sticky_announcements_enabled?, to: :exp_context, allow_nil: true

    # user - User that feed is built for
    # feed_filter - an optional FeedFilter that selectively filters the feed
    # request_id - the original request id that was used to fetch the feed, used to easily identify analytics events from the same feed "load" (read only, equal to request_context.request_id from 'feeds.feed_retrieved' event)
    # ignore_pagination - This is temporary as we figure out a more
    #   correct approach to paginating feed items. It should only ever
    #   be `true` in app/platform/objects/user_dashboard.rb
    def initialize(
      user,
      viewer:,
      feed_filter: nil,
      page: 1,
      request_id: nil,
      ignore_pagination: false,
      render_context: nil,
      exp_context: nil,
      twirp_items: [],
      ranking_model_id: nil,
      cap_filter: nil,
      per_page: PER_PAGE
    )
      @user = user
      @viewer = viewer
      @items = []
      @feed_filter = feed_filter
      @request_id = request_id
      @render_context = render_context
      @exp_context = exp_context
      @twirp_items = twirp_items
      @ranking_model_id = ranking_model_id
      @cached_records = {}

      @actor_ids = Set.new
      @user_ids = Set.new
      @release_ids = Set.new
      @discussion_ids = Set.new
      @repository_ids = Set.new
      @user_list_ids = Set.new
      @pull_request_ids = Set.new
      @pull_request_review_ids = Set.new
      @pull_request_review_comment_ids = Set.new
      @feed_post_ids = Set.new
      @feed_post_comment_ids = Set.new
      @issue_ids = Set.new
      @pull_request_comment_ids = Set.new
      @issue_comment_ids = Set.new
      @push_ids = Set.new
      @commit_comment_ids = Set.new

      @page = page
      @per_page = per_page
      @ignore_pagination = ignore_pagination
      @cap_filter = cap_filter
    end

    def build
      GitHub.dogstats.distribution_time("conduit.build_feed", tags:) do
        # This paginator holds the paging information
        # even though @items is the rendered list.
        # They work _t o g e t h e r_ 🤝
        @paginator = if ignore_pagination
          @twirp_items
        else
          GitHub::SimplePagination.paginate_collection(@twirp_items, per_page:, page:)
        end

        # does this need to move up?
        GitHub.dogstats.distribution_time("conduit.populate_resource_ids", tags:) do
          populate_resource_ids(@paginator)
        end

        @items = build_feed_items(@paginator)

        if cap_filter.present?
          @items = cap_filter.authorized_resources(@items)
        end

        @items.compact!

        after_build

        self
      end
    end

    def after_build
      # Override
    end

    def async_user
      Platform::Loaders::ActiveRecord.load(::User, user.id)
    end

    def empty?
      items.empty?
    end

    def filtered?
      feed_filter.present? && !feed_filter.include_all?
    end

    def total
      @twirp_items.size
    end

    def for_you_context?
      render_context == FOR_YOU_CONTEXT
    end

    def org_context?
      render_context == ORG_CONTEXT
    end

    def profile_activity_context?
      render_context == PROFILE_ACTIVITY_CONTEXT
    end

    def list_context?
      render_context == LIST_CONTEXT
    end

    def error_context?
      render_context == ERROR
    end

    private

    attr_reader :user, :actor_ids, :user_ids, :release_ids, :discussion_ids, :feed_post_ids,
                :feed_post_comment_ids, :repository_ids, :user_list_ids, :pull_request_ids, :page, :per_page,
                :feed_filter, :ignore_pagination, :issue_ids, :render_context, :cap_filter

    def build_feed_items(twirp_items, parent_idx: nil)
      return [] if twirp_items.empty?

      feed_items = twirp_items.filter_map.with_index do |item, idx|
        is_related_item = parent_idx.present?
        is_rollup_parent_item = item.related_items.any?

        position = if is_related_item
          parent_idx
        else
          idx
        end

        sub_position = if is_related_item
          idx + 1
        elsif is_rollup_parent_item
          0
        else
          nil
        end

        FeedItem.build(
          item,
          actor: users_by_id[item.actor&.id],
          subject: subject_for(item: item),
          related_items: build_feed_items(item.related_items, parent_idx: idx),
          idx: position,
          sub_idx: sub_position,
          feed: self,
          viewer: viewer,
        )
      end

      replace_push_events(feed_items:)
    end

    def replace_push_events(feed_items:, parent_idx: nil)
      feed_items.flat_map.with_index do |item, idx|
        is_related_item = parent_idx.present?
        is_rollup_parent_item = item.related_items.any?

        position = if is_related_item
          parent_idx
        else
          idx
        end

        sub_position = if is_related_item
          idx + 1
        elsif is_rollup_parent_item
          0
        else
          nil
        end

        if item.class == FeedItem::PushEvent
          push_event_class(item)&.new(
            item.twirp_item,
            actor: item.actor,
            subject: item.subject,
            related_items: replace_push_events(feed_items: item.related_items, parent_idx: idx),
            idx: item.idx,
            sub_idx: item.sub_idx,
            feed: self,
            viewer: viewer
          )
        else
          item
        end
      end.compact
    end

    def push_event_class(item)
      if item.subject.created?
        FeedItem::CreatePush
      elsif item.subject.deleted?
        FeedItem::DeletePush
      else
        FeedItem::PushEvent
      end
    end

    def subject_for(item:)

      case item.event_type.to_sym
      when :member_add_to_repo
        repository = repositories_by_id[item.repository_subject&.id]
        member = users_by_id[item.repository_subject&.member_id]
        return RepositoryMembership.new(repository:, member:)
      end

      case item.subject_type
      when :SUBJECT_TYPE_RELEASE
        releases_by_id[item.release_subject&.id]
      when :SUBJECT_TYPE_DISCUSSION
        discussions_by_id[item.discussion_subject&.id]
      when /REPOSITORY/
        repositories_by_id[item.repository_subject&.id]
      when :SUBJECT_TYPE_USER_LIST_ITEM
        user_list = user_lists_by_id[item.user_list_item_subject&.user_list&.id]
        repository = repositories_by_id[item.user_list_item_subject&.repository&.id]
        return unless user_list && repository
        UserListItem.new(
          user_list: user_list,
          repository: repository,
        )
      when :SUBJECT_TYPE_USER
        user = users_by_id[item.user_subject&.id]
        return if user&.ghost?
        user
      when :SUBJECT_TYPE_PULL_REQUEST
        pull_requests_by_id[item.pull_request_subject&.id]
      when :SUBJECT_TYPE_PULL_REQUEST_REVIEW
        pull_request_reviews_by_id[item.pull_request_review_subject&.id]
      when :SUBJECT_TYPE_PULL_REQUEST_REVIEW_COMMENT
        pull_request_review_comments_by_id[item.pull_request_review_comment_subject&.id]
      when :SUBJECT_TYPE_FEED_POST
        feed_posts_by_id[item.feed_post_subject&.id]
      when :SUBJECT_TYPE_ISSUE
        issues_by_id[item.issue_subject&.id]
      when :SUBJECT_TYPE_PULL_REQUEST_COMMENT
        pull_request_comments_by_id[item.pull_request_comment_subject&.id]
      when :SUBJECT_TYPE_ISSUE_COMMENT
        issue_comments_by_id[item.issue_comment_subject&.id]
      when :SUBJECT_TYPE_PUSH
        pushes_by_id[item.push_subject&.id]
      when :SUBJECT_TYPE_COMMIT_COMMENT
        commit_comments_by_id[item.commit_comment_subject&.id]
      when :SUBJECT_TYPE_WIKI_PUSH
        wiki_push_subject(item)
      else
        nil
      end
    end

    def users_by_id
      @users_by_id ||= User.where(id: @actor_ids + @user_ids)
        .includes(:sponsors_listing, :profile)
        .index_by(&:id)
    end

    def releases_by_id
      relationships = { discussion: { repository: :owner }, repository: :owner, mentions: :profile }
      @releases_by_id ||= Releases::Public.load_releases(@release_ids.to_a, relationships: relationships)
        .index_by(&:id)
    end

    def discussions_by_id
      @discussions_by_id ||= Discussion.where(id: @discussion_ids)
        .includes(:category, :user, repository: :owner)
        .filter { |d| d.body.present? }
        .index_by(&:id)
    end

    def repositories_by_id
      @repositories_by_id ||= Repositories::Public.load_repositories(@repository_ids.to_a)
        .includes(:owner, :primary_language, :parent)
        .index_by(&:id)
    end

    def user_lists_by_id
      @user_lists_by_id ||= UserList.where(id: @user_list_ids)
        .includes(:user)
        .index_by(&:id)
    end

    def pull_requests_by_id
      @pull_requests_by_id ||= Prelude.wrap( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        PullRequest.where(id: @pull_request_ids)
          .includes(
            :user,
            repository: :owner,
            issue: [:labels, :latest_user_content_edit, merge_events: :actor, repository: :owner],
          )
        )
        .select { |pr| pr.repository&.active? }
        .index_by(&:id)
    end

    def pull_request_reviews_by_id
      @pull_request_reviews_by_id ||= PullRequestReview.where(id: @pull_request_review_ids)
        .includes(:pull_request)
        .index_by(&:id)
    end

    def pull_request_review_comments_by_id
      @pull_request_review_comments_by_id ||= PullRequestReviewComment.where(id: @pull_request_review_comment_ids)
        .includes(:pull_request)
        .index_by(&:id)
    end

    def feed_posts_by_id
      @feed_posts_by_id ||= FeedPost
        .includes(:author, :owner, :topic, comments: [:user])
        .where(id: @feed_post_ids).index_by(&:id)
    end

    def issues_by_id
      @issues_by_id ||= Prelude.wrap( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          Issue.where(id: @issue_ids)
          .includes(:repository, :user, :labels)
        )
        .index_by(&:id)
    end

    def pull_request_comments_by_id
      @pull_request_comments_by_id ||= IssueComment
        .with_pull_request
        .includes(:user, :repository, [issue: :pull_request])
        .where(id: @pull_request_comment_ids)
        .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def issue_comments_by_id
      @issue_comments_by_id ||= IssueComment
        .includes(:user, :repository, :issue)
        .where(id: @issue_comment_ids)
        .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def pushes_by_id
      @pushes_by_id ||= Repositories.domain
        .pushes
        .by_ids(ids: @push_ids.to_a)
        .index_by(&:id)
    end

    def commit_comments_by_id
      @commit_comments_by_id ||= CommitComment
        .includes(:repository, :user)
        .where(id: @commit_comment_ids)
        .index_by(&:id)
    end

    def wiki_push_subject(item)
      {
        repository: repositories_by_id[item.wiki_push_subject&.repository&.id],
        updates: item.wiki_push_subject&.updates || []
      }
    end

    def populate_resource_ids(twirp_items)
      twirp_items.each do |item|
        populate_resource_ids(item.related_items)
        @actor_ids << item.actor&.id

        case item.subject_type
        when TwirpHelper.release_subject_type
          @release_ids << item.release_subject&.id
          @user_ids << item.release_subject&.repository&.owner&.id
          @repository_ids << item.release_subject&.repository&.id
        when TwirpHelper.discussion_subject_type
          @discussion_ids << item.discussion_subject&.id
        when TwirpHelper.repository_subject_type
          @repository_ids << item.repository_subject&.id
          if item.event_type.to_sym == :member_add_to_repo
            @user_ids << item.repository_subject&.member_id
          end
          if item.event_type.to_sym == :forked_repo
            @user_ids << item.repository_subject&.repository&.parent_owner_id
          end
        when TwirpHelper.user_subject_type
          @user_ids << item.user_subject&.id
        when TwirpHelper.user_list_item_subject_type
          @user_list_ids << item.user_list_item_subject&.user_list&.id
          @repository_ids << item.user_list_item_subject&.repository&.id
        when TwirpHelper.pull_request_subject_type
          @pull_request_ids << item.pull_request_subject&.id
        when TwirpHelper.pull_request_review_subject_type
          @pull_request_review_ids << item.pull_request_review_subject&.id
        when TwirpHelper.pull_request_review_comment_subject_type
          @pull_request_review_comment_ids << item.pull_request_review_comment_subject&.id
        when TwirpHelper.pull_request_comment_subject_type
          @user_ids << item.pull_request_comment_subject&.author&.id
          @pull_request_comment_ids << item.pull_request_comment_subject&.id
          @repository_ids << item.pull_request_comment_subject&.repository&.id
        when TwirpHelper.issue_comment_subject_type
          user_ids << item.issue_comment_subject&.author&.id
          @issue_comment_ids << item.issue_comment_subject&.id
          @repository_ids << item.issue_comment_subject&.repository&.id
        when TwirpHelper.feed_post_subject_type
          @feed_post_ids << item.feed_post_subject&.id
        when TwirpHelper.issue_subject_type
          @issue_ids << item.issue_subject&.id
        when TwirpHelper.push_subject_type
          @push_ids << item.push_subject&.id
        when TwirpHelper.commit_comment_subject_type
          @commit_comment_ids << item.commit_comment_subject&.id
        when TwirpHelper.wiki_push_subject_type
          @repository_ids << item.wiki_push_subject&.repository&.id
        end
      end

      # Preload feed post comment IDs for collecting
      # comment reaction data in Conduit::Web::Feed
      if feed_post_ids.any?
        @feed_post_comment_ids = FeedPostComment
          .where(feed_post_id: feed_post_ids)
          .pluck(:id)
      end
    end

    memoize def pagination_enabled?
      !ignore_pagination
    end

    def tags
      ["render_context:#{render_context}"]
    end
  end
end
