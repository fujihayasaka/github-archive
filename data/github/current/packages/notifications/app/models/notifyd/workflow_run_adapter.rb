# typed: false
# frozen_string_literal: true

module Notifyd
  class WorkflowRunAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    class EmailBody < SimpleDelegator
      def initialize(subject:, workflow_run:)
        renderer = BridgeMailRenderer.new(
          subject: subject,
          user: workflow_run.check_suite.creator,
          comment: WorkflowRunApprovalNotification.new(workflow_run),
          message_class: ::Newsies::Emails::WorkflowRunApprovalNotification,
        )

        super(renderer)
      end
    end

    delegate :permalink, :message_id,
      to: :subject

    def matches?
      return repository.present? && repository.owner.present? && GateRequest.find_by(id: context[:gate_request_id])&.requires_manual_action? if trigger == "approval_requested"
      repository.present?
    end

    def notify_feature_flag
      GitHub.flipper[:notifyd_enable_ci_activity]
    end

    def notification_id
      user = subject&.check_suite&.creator
      if user.present? && GitHub.flipper[:notifyd_approval_requested_change_notification_id].enabled?(user)
        permalink(include_host: false) + "/request/#{context[:gate_request_id]}"
      else
        permalink(include_host: false)
      end
    end

    def repository_id
      repository.id
    end

    def repository
      @repository ||= subject.repository
    end

    def owner_id
      repository.owner.id
    end

    def owner_type
      repository.owner.user? ? :user : :organization
    end

    def authzd_attributes
      subject.permissions_wrapper.serialized_subject_attributes
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def trigger
      context[:operation]
    end

    def mobile_layout
      return unless trigger == "approval_requested"

      Mobile::WorkflowApprovalRenderer.new(
        workflow_run: subject,
        repository: T.must(repository),
        actor_login: T.must(context[:actor_login])
      ).render
    end

    def email_layout
      title = "Deployment review in #{repository.name_with_display_owner}"
      reply_to = Email::NoReplyAddress.new(name: repository.name_with_display_owner, handle: repository.to_s)
      email_body = EmailBody.new(subject: title, workflow_run: subject)
      headers = EmailHeaders.new(subject, repository, context[:actor_login])
        .with_reply_to(reply_to)
        .build

      Notifyd::Proto::Layouts::Email::Raw.new({
        subject: title,
        body: email_body.parts.map(&:to_h),
        headers: headers,
        to: reply_to.to_s,
      })
    end

    def explicit_recipients
      [
        {
          reason: "approval_requested",
          users: User.where(id: context[:approver_ids]).order(:id)
        }
      ]
    end

    def related_topics
      [{ type: "repository", value: repository.id.to_s }]
    end

    def attributes
      []
    end

    def feature_switches
      { notify_actor: true }
    end

  end
end
