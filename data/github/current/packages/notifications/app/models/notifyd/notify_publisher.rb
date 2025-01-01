# typed: true
# frozen_string_literal: true

require "notifyd-client"

module Notifyd
  class NotifyPublisher
    PAYLOAD_SIZE_TO_COMPRESS = 1000 # 1KiB

    def self.explicit_recipient_batch_size
      250
    end

    def self.notifyd_enabled?
      return false if GitHub.enterprise?
      return false unless GitHub.flipper[:publish_events_to_notifyd].enabled?
      true
    end

    def initialize(aqueduct_factory: nil)
      @aqueduct_factory = aqueduct_factory
    end

    # Public: Asynchronously publishes hydro messages to trigger notification delivery through notifyd.
    #
    # actor_id       - id of the user who initiates the notification
    # subject_id     - id of the resource related to the notification. E.g. if someone was mentioned in an issue comment,
    #                  the subject of the notification would be the IssueComment instance containing the mention.
    # subject_klass  - class name of the subject
    # context        - key-value hash of attributes that will be forwarded to the subject's adapter class. Each
    #                  subject requires a matching `Notifyd::*Adapter` class provides the necessary data
    #                  to generate the payload of a Notify hydro message. The content of the context parameter
    #                  and the adapter classes are defined and maintained by Notifyd integrators.
    # Returns nothing.
    def async_publish(actor_id:, subject_id:, subject_klass:, context: {})
      return unless GitHub.flipper[:publish_events_to_notifyd].enabled?

      job_class = Notifyd::PublishNotifyMessageJob
      # Once a subject is created/updated, hamzo verifies if the content is spammy.
      # We need to give the job 10 seconds to be run. This time allows hamzo to verify if user that triggered the notification is spammy.
      if GitHub::SpamChecker.external_spamminess_check_enabled?
        job_class = job_class.set(wait: GitHub::SpamChecker::DELAY_FOR_EXTERNAL_CHECKS)
      end

      # NOTE: (@franciscoj 18/08/2023) This is the moment in which we can
      # consider that the journey of a notify event starts.
      GitHub.dogstats.increment("notifyd.delivery", tags: %w[type:notify status:enqueued])
      job_class.perform_later(
        actor_id: actor_id,
        subject_id: subject_id,
        subject_klass: subject_klass,
        context: context,
        triggered_at: Time.now
      )
    end

    # Public: Publishes hydro messages to trigger notification delivery through notifyd.
    #
    # actor_id            - id of the user who initiates the notification
    # repository_id       - id of the repository associated to the notification's subject
    # authzd_attributes   - array of authzd attributes that will be forwarded to authzd to evaluate
    #                       the policy for the `receive_notification` action and the notification's subject.
    #                       The authzd attributes of a model are usually defined in a permissions wrapper class
    #                       and can be accessed via model_instance.permissions_wrapper.serialized_subject_attributes
    # saml_enforcement    - hash containing data to enforce a valid SAML session.
    #                       The hash should either provide the id of the organization owning the notification's subject:
    #                       { organization_id: [owning_organization.id] } or { skip_enforcement: true } if the subject
    #                       is not owned by an organization and thus SAML shouldn't be enforced. SAML enforcement needs
    #                       to be explicitly skipped. Providing `nil` for `organization_id` will throw an error.
    # mobile_layout       - Protobuf instance of a notification layout that should be used to render a mobile push notification.
    #                       The protobufs for mobile layouts are generated in https://github.com/github/notifyd/blob/main/ruby/lib/notifyd/proto/layouts/mobile/layouts_pb.rb
    # email_layout       - Protobuf instance of a email layout that should be used to render an email message.
    #                       The protobufs for email layouts are generated in https://github.com/github/notifyd/blob/main/ruby/lib/notifyd/proto/layouts/email/layouts_pb.rb
    # explicit_recipients - Array of hashes providing a reason string and user objects.
    #                       Notifyd will use this array of hashes to determine recipients of the notification. Example:
    #                       Assuming the comment "Hello @user and @other_user, you should join @github/team",
    #                       we'd generate the following array to tell Notifyd which users to notify:
    #                       [
    #                         { reason: "mention", users: [user] },
    #                         { reason: "mention", users: [other_user] },
    #                         { reason: "team_mention", users: [member1, member2, member3] }
    #                       ]
    # subject             - The resource related to the notification. E.g. if someone was mentioned in an issue comment,
    #                       the subject of the notification would be the IssueComment instance containing the mention.
    # triggered_at        - The timestamp of the time when the notifyd was called to trigger the hydro message.
    # owner_id            - Id of the organization or user owning the subject used by notifyd to prevent spammy notifications
    # owner_type          - Type of the owner of the subject (currently organization or user)
    #
    # Returns nothing.
    def publish(actor_id:, repository_id:, authzd_attributes:, saml_enforcement:, mobile_layout:,
                explicit_recipients:, subject:, triggered_at:, trigger: nil, attributes: nil,
                owner_id: nil, owner_type: nil, email_layout: nil, related_topics: nil,
                feature_switches: {}, reason_groups: {}, notification_id: nil)

      return unless self.class.notifyd_enabled?

      actor = User.find_by(id: actor_id)

      if !valid?(actor: actor, subject: subject)
        GitHub.dogstats.increment("notifyd.delivery", tags: %w[type:notify status:skipped reason:invalid_actor])
        return
      end

      message = {
        actor: {
          id: actor&.id
        },
        context: {
          repository_id: repository_id,
          owner_id: owner_id,
          owner_type: SubjectAdapter.owner_type_enum(owner_type),
          trigger: trigger,
        },
        authorization: {
          authzd_attributes: authzd_attributes.map { |a| pack_into_pb_any(a) },
          saml_enforcement: saml_enforcement
        },
        rendering: {
          mobile: mobile_layout,
          email: email_layout
        },
        tracking: {
          triggered_at: triggered_at,
          subject_metadata: subject_metadata(subject)
        },
        # TODO(abeaumont): We keep the old subject adapter call for backwards compatibility.
        # Once all the jobs receive a notification_id, the subject adapter call (and implementation)
        # should go away.
        notification_id: notification_id || SubjectAdapter.notification_id_from_subject(subject),
        related_topics: related_topics,
        attributes: attributes,
        subject: {
          type: subject.class.name,
          value: subject.id.to_s
        },
        config: {
          reason_groups: reason_groups,
        },
        feature_swiches: Google::Protobuf::Map.new(:string, :bool).tap do |pb|
          feature_switches&.each { |name, enabled| pb[name] = enabled }
        end
      }

      recipients = Publishing::RecipientGroups.new(groups: explicit_recipients).filter_for(
        feature_flag: SubjectAdapter.notify_feature_flag_from_subject(subject)
      )
      message = { explicit_recipients: recipients }.merge(message)
      publish_message(message)
    end

    private

    def publish_message(message)
      headers = MessageHeaders.new.with_github_env.with_tenant_context.with_telemetry
      headers[:producer] = "github-notifyd"

      aqueduct_client = Aqueduct.default_client_for(factory: @aqueduct_factory)

      payload = Aqueduct::ProtobufPayload.new(message)
      payload = Aqueduct::DeflatedPayload.new(payload) if payload.bytesize >= PAYLOAD_SIZE_TO_COMPRESS
      headers = Aqueduct.populate_headers(headers, payload: payload)

      # GitHub::Aqueduct::Job.enqueue_hydro_message_job already adds error handling,
      # circuit breaker checks and stats around Aqueduct's RPC calls
      result = GitHub::Aqueduct::Job.enqueue_hydro_message_job(
        payload.bytes,
        queue: Aqueduct::QUEUE,
        headers: headers.to_h,
        client: aqueduct_client,
      )

      result = result.rescue do |err|
        if err.is_a?(::GitHub::Aqueduct::Job::UnavailableError)
          GitHub.dogstats.increment("notifyd.delivery", tags: %w[type:notify status:failed reason:aqueduct_unavailable])
          GitHub::Result.error(Aqueduct::UnavailableError.new) # Replace it with our internal error class
        else
          GitHub.dogstats.increment("notifyd.delivery", tags: %w[type:notify status:failed reason:unknown_error])
          GitHub::Result.error(err)
        end
      end

      # Force the result to raise so the method's API is the same as before
      result.value!
    end

    def valid?(actor:, subject:)
      validation = Publishing::ActorValidation.new(actor: actor).validate

      GitHub.dogstats.increment(
        "notifyd.publish_message.actor_validation",
        tags: [
          "reason:#{validation.reason}",
          "valid:#{validation.valid?}",
        ]
      )

      unless validation.valid?
        GitHub.logger.info("skipping message draft creation", {
          "gh.actor.id" => actor&.id.to_s,
          "gh.notifyd.subject.type" => subject&.class&.name.to_s,
          "gh.notifyd.subject.id" => subject&.id.to_s,
          "gh.notifyd.reason" => validation.reason
        })
      end

      validation.valid?
    end

    def pack_into_pb_any(data)
      Google::Protobuf::Any.new.tap { |any| any.pack(data) }
    end

    def subject_metadata(subject)
      list = subject.try(:notifications_list)
      thread = subject.try(:notifications_thread)
      return {} unless list && thread

      {
        list_id: Newsies::List.to_id(list).to_s,
        list_type: Newsies::List.to_type(list),
        thread_id: Newsies::Thread.to_id(thread).to_s,
        thread_type: Newsies::Thread.to_type(thread),
        comment_id: Newsies::Comment.to_id(subject).to_s,
        comment_type: Newsies::Comment.to_type(subject)
      }
    end
  end
end
