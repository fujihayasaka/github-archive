# typed: true
# frozen_string_literal: true

module Notifyd
  class GateRequestAdapter < SubjectAdapter
    prepend SubjectAdapterTracer

    class EmailBody < SimpleDelegator
      def initialize(subject:, gate_request:)
        renderer = BridgeMailRenderer.new(
          subject: subject,
          user: gate_request.user,
          comment: gate_request,
          message_class: ::Newsies::Emails::GateRequest,
        )

        super(renderer)
      end
    end

    delegate :approval_status, :check_run, :notification_id, to: :subject

    def matches?
      repository.present? && repository.owner.present? && subject.requires_manual_action?
    end

    def notify_feature_flag
      NotifyFeatureFlag.new
    end

    def repository_id
      repository.id
    end

    def owner_id
      repository.owner.id
    end

    def owner_type
      repository.owner.user? ? :user : :organization
    end

    def authzd_attributes
      workflow_run.permissions_wrapper.serialized_subject_attributes
    end

    def saml_enforcement
      owner = repository.owner
      owner.organization? ? { organization_id: owner.id } : { skip_enforcement: true }
    end

    def trigger
      context[:operation]
    end

    def mobile_layout
      Mobile::GateRequestRenderer.new(
        workflow_run: workflow_run,
        repository: T.must(repository),
        actor_login: T.must(context[:actor_login])
      ).render
    end

    def email_layout
      reply_to = Email::NoReplyAddress.new(name: repository.name_with_display_owner, handle: repository.to_s)
      headers = EmailHeaders.new(subject, repository, context[:actor_login])
        .with_reply_to(reply_to)
        .build

      Notifyd::Proto::Layouts::Email::Raw.new({
        subject: email_title,
        body: email_body.parts.map(&:to_h),
        headers: headers,
        to: reply_to.to_s,
      })
    end

    def explicit_recipients
      # We filter out those recipients whose approval is not pending.
      # This could be either due to:
      # - The recipient already having approved the gate.
      #   This is a kind of race condition, with very low probability.
      # - Most importantly, because the recipient the actor and the environment
      #   has self-reviews disabled. In this case, the recipient cannot approve.
      users = User.where(id: context[:approver_ids]).order(:id).filter do |user|
        approval_status(user) == "pending"
      end
      [
        {
          reason: "approval_requested",
          users: users
        }
      ]
    end

    def related_topics
      [
        { type: "repository", value: repository.id.to_s },
        { type: "workflow_run", value: workflow_run.id.to_s },
      ]
    end

    def attributes
      []
    end

    def feature_switches
      { notify_actor: true }
    end

    private

    def repository
      @repository ||= check_run.repository
    end

    def workflow_run
      @workflow_run ||= check_run.check_suite.workflow_run
    end

    def email_title
      "Deployment review in #{repository.name_with_display_owner}"
    end

    def email_body
      @email_body ||= EmailBody.new(subject: email_title, gate_request: subject)
    end
  end
end
