# typed: true
# frozen_string_literal: true

module Notifyd
  class DiscussionCommentAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    THREAD_TYPE = "discussion_comment".freeze
    MAX_COMMENTS = 1000
    MENTIONS_CACHE_TTL = 7.days.to_i
    MENTIONS_CACHE_STATS_KEY = "notifyd.discussion_comment_adapter.mentions_for.cache".freeze

    def matches?
      return false unless subject.discussion.present?

      repository.present? && repository.owner.present?
    end

    def notify_feature_flag
      NotifyFeatureFlag.new
    end

    def notification_id
      subject.permalink(include_host: false)
    end

    def repository_id
      repository.id
    end

    def authzd_attributes
      subject.discussion.permissions_wrapper.serialized_subject_attributes
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def mobile_layout
      return unless subject.discussion

      Mobile::DiscussionCommentRenderer.new(
        discussion_comment: subject,
        discussion: subject.discussion,
        author: Mobile::AuthorUser.new(user: actor)
      ).render
    end

    def email_layout
      nil
    end

    def related_topics
      [
        { type: "repository", value: repository.id.to_s },
        { type: THREAD_TYPE, value: subject.id.to_s },
      ]
    end

    def attributes
      nil
    end

    def explicit_recipients
      @explicit_recipients ||= begin
        return [] unless context[:current_body]

        recipients = explicit_recipients_for_legacy_mentions
        shadow_compute_explicit_recipients if stateful_mentions_shadow_enabled?
        recipients
      end
    end

    def owner_id
      repository.owner.id
    end

    def owner_type
      repository.owner.user? ? :user : :organization
    end

    def trigger
      context[:operation]
    end

    private

    def explicit_recipients_for_legacy_mentions
      recipients_with_reason(mention_diff.added_users)
    end

    def actor
      @actor ||= User.find_by(id: context[:actor_id])
    end

    def repository
      @repository ||= subject.repository
    end

    def recipients_with_reason(recipients)
      recipients.map do |mentioned_user|
        { reason: "mention", users: [mentioned_user] }
      end
    end

    def stateful_mentions_shadow_enabled?
      FeatureFlag.vexi.enabled?(:notifyd_discussion_comments_stateful_mentions, repository, default: false)
    end

    def compute_explicit_recipients
      case operation
      when Operations::DiscussionCommentOperation::Create
        grouped_recipients(recipients_to_reasons(all_mentions))
      when Operations::DiscussionCommentOperation::Update
        grouped_recipients(recipients_to_reasons(current_mentions))
      else []
      end
    end

    def current_mentions
      recipients = Hash.new { |recipients_by_user_id, user_id| recipients_by_user_id[user_id] = [] }

      add_current_user_mentions(recipients, "mention")
      add_current_user_mentions(recipients, "stateful_mention")
      add_current_team_mentions(recipients)

      recipients
    end

    def all_mentions
      recipients = current_mentions

      add_historical_mentions(recipients)

      recipients
    end

    def grouped_recipients(recipients_by_user_id)
      reasons_to_recipients = Hash.new { |recipients_by_reason, reason| recipients_by_reason[reason] = [] }

      recipients_by_user_id.each do |user_id, reasons|
        reasons.each do |reason|
          reasons_to_recipients[reason] << User.new(id: user_id)
        end
      end

      reasons_to_recipients.map { |reason, users| { reason: reason, users: users } }
    end

    def shadow_compute_explicit_recipients
      GitHub.dogstats.distribution_time("notifyd.discussion_comment_adapter.compute_explicit_recipients") do
        compute_explicit_recipients
      end
    end

    def mention_diff
      @mention_diff ||= GitHub::MentionDiff.new(
        context[:previous_body] || "",  # Empty for create operation
        context[:current_body],
        subject.async_body_context.sync
      )
    end

    def team_mentionees(teams)
      teams = teams.reject(&:notifications_disabled?)

      if FeatureFlag.vexi.enabled?(:dont_notify_epicgames_developers, default: true)
        teams = teams.reject { |team| team.id == Team::NewsiesAdapter::EPICGAMES_DEVELOPER_TEAM_ID }
      end

      mentionees = Hash.new { |mentionees_by_user_id, user_id| mentionees_by_user_id[user_id] = [] }
      teams.each do |team|
        subject.notifications_thread.subscribable_team_members(team).each do |user|
          mentionees[user.id] << "team_mention"
        end
      end

      mentionees
    end

    def recipients_to_reasons(recipients)
      recipients.transform_values!(&:uniq)
    end

    def add_current_user_mentions(recipients, reason)
      mention_diff.added_users.each do |user|
        recipients[user.id] << reason
      end
    end

    def add_current_team_mentions(recipients)
      add_team_mentions(recipients, mention_diff.added_teams)
    end

    def add_team_mentions(recipients, teams)
      recipients.merge!(team_mentionees(teams)) do |_user_id, existing_reasons, incoming_reasons|
        existing_reasons + incoming_reasons
      end
    end

    def add_historical_mentions(recipients)
      mentioned_teams = T.let(Set.new, T::Set[T.untyped])

      add_discussion_mentions(recipients)
      add_discussion_author(recipients)
      mentioned_teams.merge(subject.discussion.mentioned_teams)
      add_comment_recipients(recipients, mentioned_teams)
      add_team_mentions(recipients, mentioned_teams)
    end

    def add_discussion_mentions(recipients)
      subject.discussion.mentioned_users.each do |user|
        recipients[user.id] << "stateful_mention"
      end
    end

    def add_discussion_author(recipients)
      recipients[subject.discussion.user_id] << "author" if subject.discussion.user_id.present?
    end

    def add_comment_recipients(recipients, mentioned_teams)
      mentioned_user_ids = Set.new
      mentioned_team_ids = Set.new
      commenter_ids = Set.new
      comment_count = 0
      cache_enabled = mentions_cache_enabled?

      comments.in_batches(of: 100, order: :desc) do |comment_batch|
        batch_comments = comment_batch.to_a

        batch_comments.each do |comment|
          commenter_ids << comment.user_id if comment.user_id.present?
          comment_count += 1
        end

        mention_comments = mention_candidate_comments(batch_comments)
        preloaded_mentions = cache_enabled ? {} : preloaded_comments_with_mentions(mention_comments)

        mention_comments.each do |comment|
          ids = mentions_for(
            comment,
            cache_enabled: cache_enabled,
            preloaded_body_result: preloaded_mentions[comment.id]
          )
          mentioned_user_ids.merge(ids[:user_ids])
          mentioned_team_ids.merge(ids[:team_ids])
        end
      end

      mentioned_user_ids.each { |user_id| recipients[user_id] << "stateful_mention" }
      commenter_ids.each { |user_id| recipients[user_id] << "comment" }
      Team.where(id: mentioned_team_ids).each { |team| mentioned_teams << team } if mentioned_team_ids.any?
      GitHub.dogstats.distribution("notifyd.discussion_comment_adapter.comment_count", comment_count)
    end

    # Returns `{ user_ids: [...], team_ids: [...] }` for a single comment.
    #
    # NOTE: this uses `GitHub.cache` (memcached), which is deprecated for new
    # call sites outside of GHES. We accept that here to ship the perf win
    # quickly; a parallel PR migrates this same call to
    # `GitHub::RemoteCache::Preset`. See go/notifyd-mention-cache.
    def mentions_for(comment, cache_enabled:, preloaded_body_result: nil)
      return parse_mentions(comment, preloaded_body_result:) unless cache_enabled

      cache_key = "notifyd:discussion_comment_mentions:v1:" \
        "#{comment.id}:#{comment.updated_at.to_i}:#{comment.updated_at.usec}"

      GitHub.cache.fetch(cache_key, ttl: MENTIONS_CACHE_TTL, stats_key: MENTIONS_CACHE_STATS_KEY) do # rubocop:disable GitHub/AvoidMultisiteIncompatibleCacheUsage
        parse_mentions(comment)
      end
    end

    def parse_mentions(comment, preloaded_body_result: nil)
      body_result = preloaded_body_result || comment.async_body_result.sync
      {
        user_ids: Array(body_result.mentioned_users).map(&:id),
        team_ids: Array(body_result.mentioned_teams).map(&:id),
      }
    rescue StandardError
      { user_ids: [].freeze, team_ids: [].freeze }.freeze
    end

    def mentions_cache_enabled?
      FeatureFlag.vexi.enabled?(:notifyd_discussion_comment_mentions_memcache_enabled, default: false)
    end

    def mention_candidate_comments(batch_comments)
      batch_comments.select { |comment| comment.body&.include?("@") }
    end

    def preloaded_comments_with_mentions(batch_comments)
      return {} if batch_comments.empty?

      preloaded_results = Promise.all(batch_comments.map { |comment| comment.async_body_result.rescue { nil } }).sync

      batch_comments.each_with_index.to_h do |comment, index|
        [comment.id, preloaded_results[index]]
      end
    rescue StandardError
      {}
    end

    def comments
      @comments ||= subject.discussion.comments.reorder(created_at: :desc, id: :desc).limit(MAX_COMMENTS)
    end

    def operation
      @operation ||= Operations::DiscussionCommentOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
