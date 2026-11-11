# typed: true
# frozen_string_literal: true

module Notifyd
  class CommitCommentAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    def matches?
      return false unless subject.repository.present?
      true
    end

    def notify_feature_flag
      NotifyFeatureFlag.new(:notifyd_commit_comment_notify)
    end

    def notification_id
      subject.permalink(include_host: false)
    end

    def repository_id
      repository.id
    end

    def authzd_attributes
      subject.repository.permissions_wrapper.serialized_subject_attributes
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def mobile_layout
    end

    def email_layout
    end

    def related_topics
      [
        { type: "repository", value: repository.id.to_s },
        { type: "commit", value: subject.commit_id.to_s },
      ]
    end

    def explicit_recipients
      @explicit_recipients ||= compute_explicit_recipients
    end

    def attributes
      [
        # NOTE (abeaumont): These attributes would be necessary to actually
        # deliver these notifications to the recipients.
        # We want to drop them for now, so we comment these out.
        #
        # { name: "thread_participant_activity", value: "true" },
        # { name: "watch_activity", value: "true" },
        { name: "thread_type", value: "commit" },
        { name: "actor_id", value: actor&.id.to_s },
      ]
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
      when Operations::CommitCommentOperation::Update
        { notify_subscribers: false }
      else
        {}
      end
    end

    private

    def actor
      @actor ||= User.find_by(id: context[:actor_id])
    end

    def repository
      @repository ||= subject.repository
    end

    def operation
      @operation ||= Operations::CommitCommentOperation.try_deserialize_or_unknown(context[:operation])
    end

    def compute_explicit_recipients
      GitHub.dogstats.distribution_time("notifyd.commit_comment_adapter.compute_explicit_recipients") do
        recipients = Hash.new { |h, k| h[k] = [] }

        case operation
        when Operations::CommitCommentOperation::Create
          mentioned_users = Set.new
          mentioned_teams = Set.new
          commenter_ids = Set.new
          comments = 0
          CommitComment.where(
            repository_id: subject.repository_id,
            commit_id: subject.commit_id,
            user_hidden: 0,
          ).limit(1000).in_batches(of: 100, order: :desc).each_record do |comment|
            mentioned_users.merge(comment.mentioned_users)
            mentioned_teams.merge(comment.mentioned_teams)
            commenter_ids << comment.user_id if comment.user_id.present?
            comments += 1
          end
          GitHub.dogstats.distribution("notifyd.commit_comment_adapter.comment_count", comments)
          mentioned_users.each { |user| recipients[user.id] << "stateful_mention" }
          subject.mentioned_users.each { |user| recipients[user.id] << "mention" }
          commenter_ids.each { |commenter_id| recipients[commenter_id] << "comment" }

          regular_teams, biz_teams = mentioned_teams.partition { |t| !t.is_a?(BusinessTeam) }
          recipients.merge!(team_mentionees(regular_teams)) { |_key, val1, val2| val1 + val2 }
          if FeatureFlag.vexi.enabled?(:business_team_mentions, repository.owner, default: false)
            recipients.merge!(team_mentionees(biz_teams)) { |_key, val1, val2| val1 + val2 }
          end

          recipients.merge!(commit_author) { |_key, val1, val2| val1 + val2 }
        when Operations::CommitCommentOperation::Update
          diff = GitHub::MentionDiff.new(
            context[:previous_body].to_s,
            context[:current_body].to_s,
            subject.async_body_context.sync,
          )
          diff.added_users.each { |user| recipients[user.id] << "mention" }
          diff.added_users.each { |user| recipients[user.id] << "stateful_mention" }

          added_teams = diff.added_teams
          unless FeatureFlag.vexi.enabled?(:business_team_mentions, repository.owner, default: false)
            added_teams = added_teams.reject { |team| team.is_a?(BusinessTeam) }
          end

          recipients.merge!(team_mentionees(added_teams)) { |_key, val1, val2| val1 + val2 }
        end

        reasons_to_recipients = Hash.new { |h, k| h[k] = [] }
        recipients.each do |user_id, reasons|
          reasons.uniq.each do |reason|
            reasons_to_recipients[reason] << User.new(id: user_id)
          end
        end
        reasons_to_recipients.map { |reason, users| { reason: reason, users: users } }
      end
    end

    def team_mentionees(teams)
      teams = teams.reject(&:notifications_disabled?)

      # A temporary measure to prevent `@epicgames/developers` from being notified
      # See https://github.com/github/platform-health-incidents/issues/486
      if FeatureFlag.vexi.enabled?(:dont_notify_epicgames_developers, default: true)
        teams = teams.reject { |team| team.id == Team::NewsiesAdapter::EPICGAMES_DEVELOPER_TEAM_ID }
      end

      mentionees = Hash.new { |h, k| h[k] = [] }
      teams.each do |team|
        team.notifiable_members.each do |user|
          mentionees[user.id] << "team_mention"
        end
      end

      mentionees
    end

    def commit_author
      commit = subject.commit
      return {} unless commit

      author_user = commit.author || commit.committer
      return {} unless author_user

      { author_user.id => ["author"] }
    end
  end
end
