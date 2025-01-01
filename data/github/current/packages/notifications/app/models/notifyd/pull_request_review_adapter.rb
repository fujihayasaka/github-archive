# typed: true
# frozen_string_literal: true

module Notifyd
  class PullRequestReviewAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    THREAD_TYPE = "pull_request_review".freeze

    def notify_feature_flag
      NotifyFeatureFlag.new(:notifyd_pull_request_review_notify)
    end

    def notification_id
      subject.permalink(include_host: false)
    end

    def repository_id
      repository.id
    end

    def authzd_attributes
      pull_request.permissions_wrapper.serialized_subject_attributes
    end

    def matches?
      return false unless pull_request.present?
      return false unless pull_request.user.present?
      return false unless subject.user.present?
      return false unless repository.present?

      subject.approved? || subject.commented? || subject.changes_requested?
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def mobile_layout
      return unless subject.pull_request

      case operation
      when Operations::PullRequestReviewOperation::Create
        Mobile::PullRequestReviewRenderer.new(
          review: subject,
          pull_request: subject.pull_request,
        ).render
      when Operations::PullRequestReviewOperation::Update
        Mobile::PullRequestReviewUpdateRenderer.new(
          review: subject,
          pull_request: subject.pull_request,
        ).render
      end
    end

    def email_layout
      nil
    end

    def related_topics
      [
        { type: "repository", value: repository.id.to_s },
        { type: THREAD_TYPE, value: subject.id.to_s },
        { type: "pull_request", value: pull_request.id.to_s },
        { type: "issue", value: issue.id.to_s },
      ]
    end

    def attributes
      nil
    end

    def explicit_recipients
      case operation
      when Operations::PullRequestReviewOperation::Create
        [{ reason: "pull_request_reviewed", users: [pull_request.user] }]
      when Operations::PullRequestReviewOperation::Update
        diff = GitHub::MentionDiff.new(
          context[:previous_body],
          context[:current_body],
          issue.async_body_context.sync
        )
        mentionees = diff.added_users
        if mentionees.empty?
          []
        else
          [{ reason: "mention", users: mentionees }]
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
      case operation
      when Operations::PullRequestReviewOperation::Create
        "pull_request_reviewed"
      else
        context[:operation]
      end
    end

    private

    def repository
      @repository ||= subject.repository
    end

    def pull_request
      @pull_request ||= subject.pull_request
    end

    def issue
      @issue ||= pull_request.issue
    end

    def operation
      @operation ||= Operations::PullRequestReviewOperation.try_deserialize_or_unknown(context[:operation])
    end
  end
end
