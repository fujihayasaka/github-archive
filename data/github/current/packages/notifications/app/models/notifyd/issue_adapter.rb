# typed: true
# frozen_string_literal: true

module Notifyd
  class IssueAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    RelatedTopics = T.type_alias { T::Array[T::Hash[Symbol, String]] }
    Attributes = T.type_alias { T::Array[T::Hash[Symbol, String]] }

    THREAD_TYPE = "issue".freeze

    def matches?
      # NOTE(abeaumont): There's a race condition when moving the PR check
      # to the subscription code during deployment: for some pull requests
      # the check doesn't happen in subscriptions and it doesn't happen here
      # either. We add a temporary additional check here to avoid such problem.
      if subject.pull_request?
        GitHub.dogstats.increment("notifyd.matches.count", tags: ["subject:issue", "operation:#{operation}"])
        # This adapter can be used for pull requests only for the update
        # operation, but this check also happens in a later step when there is
        # no context, and that may be a valid case.
        case operation
        when Operations::IssueOperation::Update,
             Operations::IssueOperation::Unknown
          # These are potentially valid operations for pull requests.
        else
          return false
        end

        # Again, this may be called with or without an actor. In the latter
        # case the validity is checked elsewhere, we are only concerned
        # here about the first case.
        return false if actor.present? && !GitHub::flipper[:notifyd_pull_request_notify].enabled?(actor)
      end

      repository.present? && repository.owner.present?
    end

    def notify_feature_flag
      GitHub.flipper[:notifyd_issue_notify]
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

      Mobile::IssueRenderer
      .new(issue: subject, author: Mobile::AuthorUser.new(user: actor))
      .render
    end

    def email_layout
      author = actor.present? ? Email::AuthorUser.new(user: actor) : Email::NullAuthor.new

      Email::IssueRenderer.new(issue: subject, author: author, operation: operation, context: context).render
    end

    def related_topics
      topics = T.let([
        { type: "repository", value: repository.id.to_s },
        { type: THREAD_TYPE, value: subject.id.to_s },
      ], RelatedTopics)

      case operation
      when Operations::IssueOperation::Create,
        Operations::IssueOperation::Update
        topics += subject.labels.map { |l| { type: "label", value: l.id.to_s } }
      else
        return nil
      end

      topics
    end

    def attributes
      attributes = T.let([
        { name: "thread_participant_activity", value: "true" },
        { name: "thread_type", value: THREAD_TYPE },
      ], Attributes)

      attributes += subject.labels.map { |l| { name: "has_label", value: l.id.to_s } }

      case operation
      when Operations::IssueOperation::Create,
        Operations::IssueOperation::Update
        attributes << { name: "watch_activity", value: "true" }
      else
        return nil
      end

      attributes
    end

    def explicit_recipients
      @explicit_recipients ||= explicit_recipients_with_participants
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
      @actor ||=
        case operation
        when Operations::IssueOperation::Update
          User.find_by(id: context[:actor_id])
        when Operations::IssueOperation::Create
          subject.user
        else
          subject.user
        end
    end

    def feature_switches
      case operation
      when Operations::IssueOperation::Update
        # In the case of an update, we only want to notify new mentionees.
        { notify_subscribers: false }
      else
        {}
      end
    end

    private

    def repository
      @repository ||= subject.repository
    end

    def explicit_recipients_with_participants
      case operation
      when Operations::IssueOperation::Create,
        Operations::IssueOperation::Update

        Notifyd::RecipientsHelper.new(
          subject,
          operation.serialize,
          context[:previous_body],
          context[:current_body],
        ).explicit_recipients
      else
        []
      end
    end

    def operation
      @operation ||= Operations::IssueOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
