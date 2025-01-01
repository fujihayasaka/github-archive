# typed: true
# frozen_string_literal: true

module Notifyd
  class PullRequestAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    RelatedTopics = T.type_alias { T::Array[T::Hash[Symbol, String]] }
    Attributes = T.type_alias { T::Array[T::Hash[Symbol, String]] }

    def matches?
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
      return unless actor

      Mobile::PullRequestRenderer
        .new(pull_request: subject, author: Mobile::AuthorUser.new(user: actor))
        .render
    end

    def email_layout
    end

    def related_topics
      T.let([
        { type: "repository", value: repository.id.to_s },
        { type: "pull_request", value: subject.id.to_s },
        { type: "issue", value: subject.issue.id.to_s },
      ], RelatedTopics)
    end

    def attributes
      attributes = T.let([
        { name: "thread_participant_activity", value: "true" },
        { name: "thread_type", value: "pull_request" },
        { name: "watch_activity", value: "true" },
        { name: "actor_id", value: actor&.id.to_s },
      ], Attributes)
    end

    def explicit_recipients
      case operation
      when Operations::PullRequestOperation::Create,
        Operations::PullRequestOperation::Update

        mentionees = GitHub::MentionDiff.new(
          context[:previous_body] || "", # Empty for create operation
          context[:current_body],
          subject.issue.async_body_context.sync
        ).added_users
        if mentionees.empty?
          []
        else
          [{ reason: "mention", users: mentionees }]
        end
      else
        []
      end
    end

    def owner_id
      repository.owner&.id
    end

    def owner_type
      repository.owner.user? ? :user : :organization
    end

    def trigger
      context[:operation]
    end

    def actor
      @actor ||= User.find_by(id: context[:actor_id])
    end

    def feature_switches
      # NOTE(abeaumont): Subscribers are always discarded for now as the
      # support in this adapter is limited to mobile push notifications.
      # These notifications always included all the interested recipients
      # as explicit recipients.
      # This must be changed to support email and web notifications.
      { notify_subscribers: false }
    end

    private

    def repository
      @repository ||= subject.repository
    end

    def operation
      @operation ||= Operations::PullRequestOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
