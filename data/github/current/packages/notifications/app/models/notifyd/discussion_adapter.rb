# typed: true
# frozen_string_literal: true

module Notifyd
  class DiscussionAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    THREAD_TYPE = "discussion".freeze

    def matches?
      # When Notifyd::NotifyPublisher is called asynchronously, some of the dependencies may have been removed
      # For example, the associated repository may no longer exist
      # We prevent errors by making these checks:
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
      subject.permissions_wrapper.serialized_subject_attributes
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def mobile_layout
      Mobile::DiscussionRenderer
        .new(discussion: subject, author: Mobile::AuthorUser.new(user: actor))
        .render
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

        if stateful_mentions_delivery_enabled?(repository.owner)
          compute_explicit_recipients
        else
          recipients = explicit_recipients_for_legacy_mentions
          shadow_compute_explicit_recipients if stateful_mentions_shadow_enabled?
          recipients
        end
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
      mention_diff = GitHub::MentionDiff.new(
        context[:previous_body] || "",  # Empty for create operation
        context[:current_body],
        subject.async_body_context.sync
      )
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
      FeatureFlag.vexi.enabled?(:notifyd_discussions_stateful_mentions, repository, default: false)
    end

    def compute_explicit_recipients
      recipients = case operation
      when Operations::DiscussionOperation::Create
        add_author(current_mentions)
      when Operations::DiscussionOperation::Update
        current_mentions
      else
        return []
      end

      grouped_recipients(recipients_to_reasons(recipients))
    end

    def current_mentions
      recipients = Hash.new { |recipients_by_user_id, user_id| recipients_by_user_id[user_id] = [] }

      add_current_user_mentions(recipients, "mention")
      add_current_user_mentions(recipients, "stateful_mention")
      add_current_team_mentions(recipients)

      recipients
    end

    def add_current_user_mentions(recipients, reason)
      mention_diff.added_users.each { |user| recipients[user.id] << reason }
    end

    def add_current_team_mentions(recipients)
      recipients.merge!(team_mentionees(mention_diff.added_teams)) do |_user_id, existing_reasons, incoming_reasons|
        existing_reasons + incoming_reasons
      end
    end

    def add_author(recipients)
      recipients.merge!(author) do |_user_id, existing_reasons, incoming_reasons|
        existing_reasons + incoming_reasons
      end
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

    def recipients_to_reasons(recipients)
      recipients.transform_values!(&:uniq)
    end

    def shadow_compute_explicit_recipients
      GitHub.dogstats.distribution_time("notifyd.discussion_adapter.compute_explicit_recipients") do
        compute_explicit_recipients
      end
    end

    def mention_diff
      @mention_diff ||= GitHub::MentionDiff.new(
        context[:previous_body] || "",
        context[:current_body].to_s,
        subject.async_body_context.sync,
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

    def author
      return {} unless subject.user_id

      { subject.user_id => ["author"] }
    end

    def operation
      @operation ||= Operations::DiscussionOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
