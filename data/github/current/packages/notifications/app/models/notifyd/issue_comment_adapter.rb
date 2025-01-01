# typed: true
# frozen_string_literal: true

module Notifyd
  class IssueCommentAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    def matches?
      return false unless subject.issue.present? && repository.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      # NOTE(abeaumont): There's a race condition when moving the PR check
      # to the subscription code during deployment: for some pull requests
      # the check doesn't happen in subscriptions and it doesn't happen here
      # either. We add a temporary additional check here to avoid such problem.
      if subject.issue.pull_request?
        GitHub.dogstats.increment("notifyd.matches.count", tags: ["subject:issue_comment", "operation:#{operation}"])

        # This may be called with or without an actor. In the latter case the
        # validity is checked elsewhere, we are only concerned here about the
        # first case.
        return false if actor.present? && !GitHub::flipper[:notifyd_pull_request_notify].enabled?(actor)
      end

      true
    end

    def notify_feature_flag
      GitHub.flipper[:notifyd_issue_comment_notify]
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
        context: context
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

      topics += subject.issue.labels.map { |l| { type: "label", value: l.id.to_s } }
    end

    def explicit_recipients
      @explicit_recipients ||= explicit_recipients_with_participants
    end

    def attributes
      attributes = [
        { name: "thread_participant_activity", value: "true" },
        { name: "watch_activity", value: "true" },
        { name: "thread_type", value: subject.issue.pull_request? ? "pull_request" : "issue" },
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

    def repository
      @repository ||= subject.repository
    end

    def explicit_recipients_with_participants
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

    def operation
      @operation ||= Operations::IssueCommentOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
