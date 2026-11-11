# typed: true
# frozen_string_literal: true

module Notifyd
  class IssueCommentAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    MAX_COMMENTS = 1000

    def matches?
      return false unless subject.issue.present? && repository.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      # NOTE(abeaumont): There's a race condition when moving the PR check
      # to the subscription code during deployment: for some pull requests
      # the check doesn't happen in subscriptions and it doesn't happen here
      # either. We add a temporary additional check here to avoid such problem.
      if subject.issue.pull_request?
        GitHub.dogstats.increment("notifyd.matches.count", tags: ["subject:issue_comment", "operation:#{operation}"])
      end

      true
    end

    def notify_feature_flag
      NotifyFeatureFlag.new
    end

    def notification_id
      subject.permalink(include_host: false) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def repository_id
      repository.id
    end

    def authzd_attributes
      subject.permissions_wrapper.serialized_subject_attributes
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def mobile_layout
      return unless actor
      return unless subject.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      Mobile::IssueCommentRenderer.new(
        issue_comment: subject,
        issue: subject.issue,
        author: Mobile::AuthorUser.new(user: actor)
      ).render
    end

    def email_layout
      return unless actor
      return unless subject.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return if subject.issue.pull_request?

      author = Email::AuthorUser.new(user: actor)

      Email::IssueCommentRenderer.new(
        comment: subject,
        issue: subject.issue,
        author: author,
        context: context,
        beacon_url: email_beacon_url(actor, "issue_comment", related_topics)
      ).render
    end

    def related_topics
      topics = T.let([
        { type: "repository", value: repository.id.to_s },
        { type: "issue", value: subject.issue.id.to_s },
      ], T::Array[T::Hash[Symbol, String]])

      if subject.issue.pull_request?
        topics << { type: "pull_request", value: subject.issue.pull_request.id.to_s }
      end

      topics
    end

    def explicit_recipients
      @explicit_recipients ||= begin
        return [] unless context[:current_body]

        if stateful_mentions_delivery_enabled?(repository.owner)
          GitHub.dogstats.distribution_time("notifyd.issue_comment_adapter.compute_explicit_recipients") { compute_explicit_recipients }
        else
          shadow_compute_explicit_recipients if stateful_mentions_shadow_enabled?
          explicit_recipients_for_legacy_mentions
        end
      end
    end

    def compute_explicit_recipients
      case operation
      when Operations::IssueCommentOperation::Create
        grouped_recipients(recipients_to_reasons(all_mentions))
      when Operations::IssueCommentOperation::Update
        grouped_recipients(recipients_to_reasons(current_mentions))
      else
        []
      end
    end

    def shadow_compute_explicit_recipients
      GitHub.dogstats.distribution_time("notifyd.issue_comment_adapter.compute_explicit_recipients") do
        compute_explicit_recipients
      end
    end

    def attributes
      attributes = [
        { name: "thread_participant_activity", value: "true" },
        { name: "watch_activity", value: "true" },
        { name: "thread_type", value: subject.issue.pull_request? ? "pull_request" : "issue" },
        { name: "actor_id", value: actor&.id.to_s },
      ]
      attributes += subject.issue.labels.map { |l| { name: "has_label", value: l.id.to_s } }
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

    def feature_switches
      case operation
      when Operations::IssueCommentOperation::Update
        {
          notify_subscribers: false
        }
      else
        {}
      end
    end

    private

    def actor
      @actor ||= User.find_by(id: context[:actor_id])
    end

    def mention_diff
      @mention_diff ||= GitHub::MentionDiff.new(
        context[:previous_body] || "",
        context[:current_body],
        subject.async_body_context.sync,
      )
    end

    def repository
      @repository ||= subject.repository
    end

    def explicit_recipients_for_legacy_mentions
      case operation
      when Operations::IssueCommentOperation::Create, Operations::IssueCommentOperation::Update
        Notifyd::RecipientsHelper.new(
          subject,
          context[:operation],
          context[:previous_body],
          context[:current_body],
        ).explicit_recipients
      else
        []
      end
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

      add_issue_mentions(recipients)
      add_issue_author(recipients)
      mentioned_teams.merge(subject.issue.mentioned_teams)
      add_comment_recipients(recipients, mentioned_teams)
      add_team_mentions(recipients, mentioned_teams)
    end

    def add_issue_mentions(recipients)
      subject.issue.mentioned_users.each do |user|
        recipients[user.id] << "stateful_mention"
      end
    end

    def add_issue_author(recipients)
      recipients[subject.issue.user_id] << "author" if subject.issue.user_id.present?
    end

    def add_comment_recipients(recipients, mentioned_teams)
      mentioned_user_ids = Set.new
      commenter_ids = Set.new
      comment_count = 0

      comments.in_batches(of: 100, order: :desc) do |comment_batch|
        batch_comments = comment_batch.to_a

        batch_comments.each do |comment|
          commenter_ids << comment.user_id if comment.user_id.present?
          comment_count += 1
        end

        preloaded_comments_with_mentions(batch_comments).each do |_comment, body_result|
          mentioned_users = body_result.mentioned_users&.to_a
          mentioned_teams_from_body = body_result.mentioned_teams&.to_a
          mentioned_users&.each { |user| mentioned_user_ids << user.id }
          mentioned_teams_from_body&.each { |team| mentioned_teams << team }
        end
      end

      mentioned_user_ids.each { |user_id| recipients[user_id] << "stateful_mention" }
      commenter_ids.each { |user_id| recipients[user_id] << "comment" }
      GitHub.dogstats.distribution("notifyd.issue_comment_adapter.comment_count", comment_count)
    end

    def preload_comment_body_results(batch_comments)
      body_results = Promise.all(batch_comments.map { |comment| comment.async_body_result }).sync

      batch_comments.zip(body_results)
    end

    def mention_candidate_comments(batch_comments)
      batch_comments.select { |comment| comment.body&.include?("@") }
    end

    def preloaded_comments_with_mentions(batch_comments)
      preload_comment_body_results(mention_candidate_comments(batch_comments))
    end

    def comments
      @comments ||= subject.issue.comments.limit(MAX_COMMENTS)
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

    def stateful_mentions_shadow_enabled?
      FeatureFlag.vexi.enabled?(:notifyd_issue_comments_stateful_mentions, repository, default: false)
    end

    def operation
      @operation ||= Operations::IssueCommentOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
