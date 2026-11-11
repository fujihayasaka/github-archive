# typed: true
# frozen_string_literal: true

module Notifyd
  class RepositoryAdvisoryAdapter < SubjectAdapter
    prepend SubjectAdapterTracer
    include GitHub::Memoizer

    def matches?
      # When Notifyd::NotifyPublisher is called asynchronously, some of the dependencies may have been removed
      # For example, the associated repository may no longer exist
      # We prevent errors by making these checks:
      repository.present? && repository.owner.present?
    end

    # NOTE: We are only computing stateful mentions here as a shadow experiment
    # (see github/notifyd#5695) and never publishing through notifyd yet. We return
    # `false` defensively so that if any caller does build this adapter and
    # publish, every recipient is filtered out by
    # `Publishing::RecipientGroups#filter_for`. This will become a real flag
    # when the publish path is wired up in a follow-up PR, provided the
    # experiment is successful.
    def notify_feature_flag
      NotifyFeatureFlag.new(false)
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
      nil
    end

    def email_layout
      nil
    end

    def related_topics
      [
        { type: "repository", value: repository.id.to_s },
        { type: "repository_advisory", value: subject.id.to_s },
      ]
    end

    def attributes
      nil
    end

    # Shadow-only: behind the notifyd_repository_advisories_stateful_mentions
    # flag we run the stateful-mention computation purely to time it via
    # dogstats.  The result is intentionally discarded, we will always
    # return [] until publishing is wired up in a follow-up effort.
    def explicit_recipients
      return [] unless context[:current_body]
      return [] unless stateful_mentions_shadow_enabled?

      shadow_compute_explicit_recipients
      []
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

    def stateful_mentions_shadow_enabled?
      FeatureFlag.vexi.enabled?(:notifyd_repository_advisories_stateful_mentions, repository, default: false)
    end

    memoize def shadow_compute_explicit_recipients
      GitHub.dogstats.distribution_time("notifyd.repository_advisory_adapter.compute_explicit_recipients") do
        compute_explicit_recipients
      end
    end

    def compute_explicit_recipients
      recipients = Hash.new { |recipients_by_user_id, user_id| recipients_by_user_id[user_id] = [] }

      case operation
      when Operations::RepositoryAdvisoryOperation::Create, Operations::RepositoryAdvisoryOperation::Update
        privileged_added_users.each { |user| recipients[user.id] << "mention" }
        privileged_added_users.each { |user| recipients[user.id] << "stateful_mention" }
        recipients.merge!(team_mentionees(privileged_added_teams)) do |_user_id, existing_reasons, incoming_reasons|
          existing_reasons + incoming_reasons
        end
      else
        return []
      end

      reasons_to_recipients = Hash.new { |recipients_by_reason, reason| recipients_by_reason[reason] = [] }
      recipients.each do |user_id, reasons|
        reasons.uniq.each do |reason|
          reasons_to_recipients[reason] << User.new(id: user_id)
        end
      end

      reasons_to_recipients.map { |reason, users| { reason: reason, users: users } }
    end

    memoize def mention_diff
      GitHub::MentionDiff.new(
        context[:previous_body] || "", # Create operations have no previous body
        context[:current_body].to_s,
        subject.async_body_context.sync,
      )
    end

    def privileged_added_users
      added_users = mention_diff.added_users
      return [] if added_users.empty?

      privileged_ids = subject.privileged_user_ids & added_users.map(&:id)
      added_users.select { |user| privileged_ids.include?(user.id) }
    end

    def privileged_added_teams
      added_teams = mention_diff.added_teams
      return [] if added_teams.empty?

      privileged_ids = subject.privileged_team_ids(added_teams.map(&:id))
      added_teams.select { |team| privileged_ids.include?(team.id) }
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

    memoize def actor
      User.find_by(id: context[:actor_id])
    end

    memoize def repository
      subject.repository
    end

    memoize def operation
      Operations::RepositoryAdvisoryOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
