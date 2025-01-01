# typed: true
# frozen_string_literal: true

module Notifyd
  class CheckSuiteAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    class EmailBody < SimpleDelegator
      def initialize(subject:, check_suite:)
        renderer = BridgeMailRenderer.new(
          subject: subject,
          user: check_suite.creator,
          comment: CheckSuiteEventNotification.new(check_suite),
          message_class: ::Newsies::Emails::CheckSuiteEventNotification,
        )

        super(renderer)
      end
    end

    include GitHub::Memoizer

    delegate :pull_request?,
      :permalink,
      :conclusion,
      :creator,
      :notification_recipients,
      :head_branch,
      :short_head_sha,
      :head_sha,
      :head_repository_id,
      :event,
      :name,
      :workflow_run,
      to: :subject

    def matches?
      repository.present? && repository.owner.present?
    end

    def notify_feature_flag
      SubjectAdapter::FeatureEnabled.new
    end

    def notification_id
      id = permalink(include_host: false)
      return id unless attempt.present?

      "#{id}##{attempt}"
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
      Mobile::CheckSuiteRenderer.new(
        check_suite: subject,
        repository: T.must(repository),
        pull_request: pull_request,
        attempt: attempt.presence || 0
      ).render
    end

    def email_layout
      reply_to = Email::NoReplyAddress.new(name: repository.name_with_display_owner, handle: repository.to_s)
      headers = EmailHeaders
        .new(subject, repository, context[:actor_login])
        .with_reply_to(reply_to)
        .build

      Notifyd::Proto::Layouts::Email::Raw.new({
        subject: email_title,
        from: Notifyd::Proto::Layouts::Email::From.new(name: creator.safe_profile_name),
        headers: headers,
        to: reply_to.to_s,
        body: email_body.parts.map(&:to_h),
      })
    end

    def related_topics
      [{ type: "repository", value: repository.id.to_s }]
    end

    def attributes
      [{ name: "failed", value: subject.failed?.to_s }]
    end

    def explicit_recipients
      [{ reason: "ci_activity", users: notification_recipients }]
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
      {
        notify_actor: true,
        notify_subscribers: false
      }
    end

    private

    def repository
      @repository ||= subject.repository
    end

    def email_title
      if pull_request.present?
        "[#{repository.name_with_display_owner}] PR run #{verb_conclusion}: #{workflow_name_with_attempt} - #{pull_request.title} (#{short_head_sha})"
      else
        "[#{repository.name_with_display_owner}] Run #{verb_conclusion}: #{workflow_name_with_attempt} - #{head_branch} (#{short_head_sha})"
      end
    end

    def email_body
      @email_body ||= EmailBody.new(subject: email_title, check_suite: subject)
    end

    def pull_request
      # there can be associated pull requests with the head_sha and branch on
      # push events, ensure the event type matches up
      return nil unless event == "pull_request"

      @_pull_request ||= repository.pull_requests.find_by(
        head_ref: head_branch,
        head_repository_id: head_repository_id,
        head_sha: head_sha,
      )
    end

    def verb_conclusion
      StatusCheckConfig.verb_state(conclusion)
    end

    def workflow_name_with_attempt
      return "#{name}, Attempt ##{attempt}" if attempt.present?
      name
    end

    memoize def attempt
      workflow_run&.current_attempt_num
    end
  end
end
