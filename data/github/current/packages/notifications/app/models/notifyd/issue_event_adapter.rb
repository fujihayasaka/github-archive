# typed: true
# frozen_string_literal: true

module Notifyd
  class IssueEventAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    RelatedTopics = T.type_alias { T::Array[T::Hash[Symbol, String]] }
    Attributes = T.type_alias { T::Array[T::Hash[Symbol, String]] }

    def matches?
      repository.present? && repository.owner.present? && issue.present?
    end

    def notify_feature_flag
      NotifyFeatureFlag.new(:notifyd_issue_event_notify)
    end

    def notification_id
      subject.permalink(include_host: false) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def repository_id
      repository.id
    end

    def authzd_attributes
      if issue.pull_request?
        issue.pull_request.permissions_wrapper.serialized_subject_attributes
      else
        issue.permissions_wrapper.serialized_subject_attributes
      end
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def mobile_layout
      return unless actor

      case operation
      when Operations::IssueOperation::Assigned
        Mobile::AssignedIssueRenderer
        .new(issue: issue, author: Mobile::AuthorUser.new(user: actor), event: subject)
        .render
      when Operations::PullRequestOperation::Assigned
        Mobile::AssignedPullRequestRenderer
        .new(pull_request: issue.pull_request, author: Mobile::AuthorUser.new(user: actor), event: subject)
        .render
      when Operations::PullRequestOperation::ReviewRequested
        Mobile::ReviewRequestedPullRequestRenderer
        .new(pull_request: issue.pull_request, author: Mobile::AuthorUser.new(user: actor), event: subject)
        .render
      else
        if issue.pull_request?
          Mobile::PullRequestRenderer
            .new(pull_request: issue.pull_request, author: Mobile::AuthorUser.new(user: actor))
            .render
        else
          Mobile::IssueRenderer
          .new(issue: issue, author: Mobile::AuthorUser.new(user: actor))
          .render
        end
      end
    end

    def email_layout
      if issue.pull_request?
        # NOTE(peter-evans): This adapter does not support web and email notifications for pull request events yet.
        nil
      else
        author = actor.present? ? Email::AuthorUser.new(user: actor) : Email::NullAuthor.new
        Email::IssueRenderer.new(issue: issue, author: author, operation: operation, context: context).render
      end
    end

    def related_topics
      topics = T.let([
        { type: "repository", value: repository.id.to_s },
        { type: "issue", value: issue.id.to_s }
      ], RelatedTopics)

      if issue.pull_request?
        topics << { type: "pull_request", value: issue.pull_request.id.to_s }
      end

      case operation
      when Operations::IssueOperation::Labeled,
        Operations::IssueOperation::Unlabeled
        topics << { type: "label", value: subject.label_id.to_s }
      when Operations::IssueOperation::Assigned,
        Operations::IssueOperation::Closed,
        Operations::IssueOperation::Reopened,
        Operations::IssueOperation::ConvertedToDiscussion,
        Operations::PullRequestOperation::Assigned,
        Operations::PullRequestOperation::ReviewRequested
        topics += issue.labels.map { |l| { type: "label", value: l.id.to_s } }
      else
        return nil
      end

      topics
    end

    def attributes
      attributes = T.let([
        { name: "thread_participant_activity", value: "true" },
        { name: "actor_id", value: actor&.id.to_s },
      ], Attributes)

      if issue.pull_request?
        attributes << { name: "thread_type", value: "pull_request" }
      else
        attributes << { name: "thread_type", value: "issue" }
      end

      attributes += issue.labels.map { |l| { name: "has_label", value: l.id.to_s } }

      case operation
      when Operations::IssueOperation::Labeled
        attributes << { name: "added_label", value: subject.label_id.to_s }
      when Operations::IssueOperation::Unlabeled
        attributes << { name: "removed_label", value: subject.label_id.to_s }
      when Operations::IssueOperation::Assigned,
        Operations::IssueOperation::Closed,
        Operations::IssueOperation::Reopened,
        Operations::IssueOperation::ConvertedToDiscussion,
        Operations::PullRequestOperation::Assigned,
        Operations::PullRequestOperation::ReviewRequested
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
      User.find_by(id: context[:actor_id])
    end

    def feature_switches
      case operation
      when Operations::IssueOperation::Assigned,
        Operations::PullRequestOperation::Assigned,
        # In the case of an assign event, we only want to notify the explicit recipients.
        Operations::PullRequestOperation::ReviewRequested
        # NOTE(peter-evans): Subscribers for pull request events are always discarded for
        # now as the support in this adapter for these events is limited to mobile push
        # notifications.
        # These notifications always included all the interested recipients as explicit
        # recipients. This must be changed to support email and web notifications.
        { notify_subscribers: false }
      else
        {}
      end
    end

    private

    def issue
      @issue ||= subject.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def repository
      @repository ||= subject.repository
    end

    def explicit_recipients_with_participants
      case operation
      when Operations::IssueOperation::Closed,
        Operations::IssueOperation::Reopened,
        Operations::IssueOperation::ConvertedToDiscussion

        Notifyd::RecipientsHelper.new(
          issue.pull_request? ? issue.pull_request : issue,
          operation.serialize,
          context[:previous_body],
          context[:current_body],
        ).explicit_recipients
      when Operations::IssueOperation::Assigned,
        Operations::PullRequestOperation::Assigned
        [{ reason: "assign", users: [User.new(id: context[:assignee_id])] }]
      when Operations::PullRequestOperation::ReviewRequested
        # NOTE(abeaumont): Filtering teams here works well for now since we are only
        # sending push notifications for this reason, but once we want email / web
        # notifications this will need to be addressed differently.
        if subject.subject.class.name == "User"
          [{ reason: "review_requested", users: [User.new(id: context[:reviewer_id])] }]
        else
          []
        end
      else
        []
      end
    end

    def operation
      if issue.pull_request?
        @operation ||= Operations::PullRequestOperation.try_deserialize(context[:operation])
      end
      @operation ||= Operations::IssueOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
