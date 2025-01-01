# typed: true
# frozen_string_literal: true

require "active_support/core_ext/numeric"

module GitHub
  module WebSocket
    PRESENCE_PREFIX = "presence-"

    LUAU_SOCKET_ID_VERSION = "V3".freeze

    # The Default Time to Live for EVERYTHING having to do with
    # these sockets in Redis.  We want to make sure that these are all
    # expiration based values, as a WebSocket is inherently a transient thing
    TTL = 1.hour.to_i

    # Length of random numbers generated for channel ids
    CHANNEL_ID_MAX = 2**32

    # Used to report an unknown channel type to datadog
    UNKNOWN_CHANNEL_TYPE = "unknown".freeze

    class << self
      delegate :logger, to: Rails

      # Is WebSocket event fanout enabled.
      def enabled?
        return @enabled if defined?(@enabled)

        # Check global live updates switch first
        return false unless GitHub.live_updates_enabled?

        true
      end

      # Configure enabled flag in tests.
      def enabled=(val)
        @enabled = val
      end

      # Internal: Get shared verify for signing socket ids & subscription messages.
      #
      # Returns singleton MessageVerifier instance.
      def luau_verifier
        @luau_verifier ||= ActiveSupport::MessageVerifier.new(GitHub.longpoll_socket_id_secret, digest: "SHA256", serializer: JSON)
      end

      def luau_sign_socket_id(session)
        sign_socket_id(session.id, session.user_id)
      end

      def luau_url(session)
        websocket_url(session.id, session.user_id)
      end

      def sign_socket_id(session_id, user_id)
        GitHub.tracer.in_span("web_socket#luau_verifier.generate", kind: :internal) do |_span|
          luau_verifier.generate(luau_socket_id(session_id, user_id))
        end
      end

      def websocket_url(session_id, user_id)
        signed_id = GitHub::WebSocket.sign_socket_id(session_id, user_id)
        "#{GitHub.urls.alive_ws_url}/_sockets/u/#{user_id}/ws?session=#{signed_id}"
      end

      def luau_session_id(session)
        OpenSSL::Digest::SHA256.hexdigest("luau-session-id-#{session.user_id}-#{session.id}")
      end

      # Public: Generate unique socket id for a given user session.
      # Timestamp is so that we only have to allow recent values and
      # don't accept sockets forever.
      def luau_socket_id(session_id, user_id)
        raise ArgumentError, "user_id cannot be nil" unless user_id

        connection_id = SecureRandom.random_number(CHANNEL_ID_MAX)
        timestamp = Time.now.to_i
        { v: LUAU_SOCKET_ID_VERSION, u: user_id, s: session_id, c: connection_id, t: timestamp }
      end

      # Public: Generate a signed channel subscription for Alive with encrypted authzd attributes
      def signed_presence_channel(channel, authzd_attributes)
        presence_channel = PRESENCE_PREFIX + channel

        # pack a full authzd request in a protobuf to be encrypted
        authzd_request = Authzd::Proto::Request.new(attributes: authzd_attributes)

        encrypted_authzd_attributes = encrypt_attributes(authzd_request.to_proto)
        # raw encrypted bytes do not encode well to JSON.  Need to base64 encode them.
        authzd_message = Base64.strict_encode64(encrypted_authzd_attributes)

        luau_verifier.generate({ c: presence_channel, t: Time.now.to_i, a: authzd_message })
      end

      # Public: Generate a signed channel subscription for Alive
      def signed_channel(channel)
        luau_verifier.generate({ c: channel, t: Time.now.to_i })
      end

      def notify_pre_receive_environment_channel(pre_receive_environment, channel_id, data = {})
        attrs = generate_authzd_attributes(pre_receive_environment)
        notify_site_admin_channel(pre_receive_environment, channel_id, data, authzd_attributes: attrs)
      end

      def notify_spam_queue_entry_channel(spam_queue_entry, channel_id, data = {})
        attrs = generate_authzd_attributes(spam_queue_entry)
        notify_site_admin_channel(spam_queue_entry, channel_id, data, authzd_attributes: attrs)
      end

      def notify_bulk_dmca_takedown_channel(bulk_dmca_takedown, channel_id, data = {})
        attrs = generate_authzd_attributes(bulk_dmca_takedown)
        notify_site_admin_channel(bulk_dmca_takedown, channel_id, data, authzd_attributes: attrs)
      end

      def notify_user_channel(user_id, channel_id, data = {})
        notify_channel(channel_id, data, authzd_attributes: [])
      end

      def notify_repository_channel(repository, channel_id, data = {})
        if repository.public?
          attrs = []
        else
          attrs = generate_authzd_attributes(repository)
        end
        notify_entity_channel(repository, channel_id, data, authzd_attributes: attrs)
      end

      def notify_deployment_channel(deployment, channel_id, data = {})
        attrs = generate_authzd_attributes(deployment)
        notify_repository_writable_channel(deployment, channel_id, data, authzd_attributes: attrs)
      end

      def notify_repository_advisory_channel(repository_advisory, channel_id, data = {})
        if repository_advisory.published?
          GitHub::WebSocket.notify_repository_channel(repository_advisory.repository, channel_id, data)
        else
          attrs = generate_authzd_attributes(repository_advisory)
          notify_repository_writable_channel(repository_advisory, channel_id, data, authzd_attributes: attrs)
        end
      end

      def notify_issue_channel(issue, channel_id, data = {})
        return unless issue.repository

        if issue.repository.public?
          attrs = []
        else
          attrs = generate_authzd_attributes(issue)
        end

        notify_entity_channel(issue, channel_id, data,
          authzd_attributes: attrs)
      end

      def notify_issue_summary_channel(issue_summary, channel_id, data = {})
        return unless issue_summary
        attrs = []
        notify_entity_channel(issue_summary, channel_id, data, authzd_attributes: attrs)
      end

      def notify_pull_request_channel(pull_request, channel_id, data = {})
        return unless pull_request.repository

        if pull_request.repository.public?
          attrs = []
        else
          attrs = generate_authzd_attributes(pull_request)
        end
        notify_entity_channel(pull_request, channel_id, data,
          authzd_attributes: attrs)
      end

      def notify_project_channel(project, channel_id, data = {})
        return unless project

        if project.public?
          attrs = []
        else
          attrs = generate_authzd_attributes(project)
        end
        notify_entity_channel(project, channel_id, data,
          authzd_attributes: attrs)
      end

      def notify_discussion_channel(discussion, channel_id, data = {})
        if discussion.public?
          attrs = []
        else
          attrs = generate_authzd_attributes(discussion)
        end
        notify_entity_channel(discussion, channel_id, data,
          authzd_attributes: attrs)
      end

      def notify_packages_migration_channel(migration_run, channel_id, data = {})
        notify_entity_channel(migration_run, channel_id, data, authzd_attributes: [])
      end

      def notify_discussion_post_channel(discussion_post, channel_id, data = {})
        attrs = generate_authzd_attributes(discussion_post)
        notify_entity_channel(discussion_post, channel_id, data, authzd_attributes: attrs)
      end

      # Notifies stacks live status updates to the subscribers
      def notify_stacks_channel(stacks_instance, channel_id, data = {})
        if stacks_instance.instance_repository.public?
          attrs = []
        else
          attrs = generate_authzd_attributes(stacks_instance.instance_repository)
        end
        notify_channel(channel_id, data, authzd_attributes: attrs)
      end

      def notify_integration_installation_channel(target, channel_id, data = {})
        attrs = generate_authzd_attributes(target)
        notify_entity_channel(target, channel_id, data, authzd_attributes: attrs)
      end

      def notify_memex_channel(memex, channel_id, data = {})
        authzd_attributes = generate_authzd_attributes(memex, memex.view_live_update_authzd_attributes)
        notify_entity_channel(memex, channel_id, data, authzd_attributes:)
      end

      def notify_custom_pattern_dry_run_channel(owner, channel_id, data = {})
        attrs = generate_authzd_attributes(owner)
        notify_entity_channel(owner, channel_id, data, authzd_attributes: attrs)
      end

      def notify_prebuild_configuration_workflow_run_channel(prebuild_configuration, channel_id, data = {})
        if prebuild_configuration.repository.public?
          authzd_attributes  = []
        else
          authzd_attributes  = generate_authzd_attributes(prebuild_configuration.repository)
        end
        notify_entity_channel(prebuild_configuration, channel_id, data, authzd_attributes: authzd_attributes)
      end

      # Returns an array of attributes necessary for authorization, serialized as Protobufs.
      def generate_authzd_attributes(subject, additional_attributes = {})
        additional_attributes
          .merge({ action: :view_live_update })
          .each_with_object(subject.permissions_wrapper.serialized_subject_attributes) do |(key, value), result|

          result << Authzd::Proto::Attribute.wrap(key, value)
        end
      end

      def notify_repository_codespaces_channel(repository, channel_id, data = {})
        return unless repository

        if repository.public?
          attrs = []
        else
          attrs = generate_authzd_attributes(repository)
        end

        notify_entity_channel(repository, channel_id, data, authzd_attributes: attrs)
      end

      def notify_business_report_export_status_channel(business_report_export, channel_id, data = {})
        return unless business_report_export

        attrs = generate_authzd_attributes(business_report_export)

        notify_entity_channel(business_report_export, channel_id, data, authzd_attributes: attrs)
      end

      def notify_react_sandbox_channel(channel_id, data = {})
        notify_channel(channel_id, data, authzd_attributes: [])
      end

      def notify_graphql_subscription_channel(channel_name, graphql_payload) # authzd_attributes are not used for graphql subscriptions because
        # subscriptions are currently user-specific: the graphql framework
        # will perform the required authz while generating the payload.
        notify_channel(channel_name, graphql_payload, authzd_attributes: [])
      end

      def notify_security_configurations_update_channel(owner, channel_id, data = {})
        return unless owner

        # Authorization for this channel is checked when rendering, configurations don't have security attributes on them.
        notify_entity_channel(owner, channel_id, data, authzd_attributes: [])
      end

      def notify_setting_orchestration_status_channel(orchestration, channel_id, data)
        return unless orchestration
        notify_entity_channel(orchestration, channel_id, data, authzd_attributes: [])
      end

      private

      # Private: Publish message to Hydro for consumption in Alive.
      def publish_message(channel, data, authzd_attributes)
        payload = {
          channel: channel,
          data: GitHub::JSON.dump(data),
        }
        if authzd_attributes.any?
          pb = Google::Protobuf::Any.new
          pb.pack(Authzd::Proto::Request.new(attributes: authzd_attributes))
          payload[:authzd_attributes] = pb
        end
        GitHub.hydro_publisher.publish(payload, schema: "live_updates.v0.Message", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
      end

      # Private: Notify all subscribes for the specific channel about updates
      # regarding 'data'.
      #
      # channel_id  - the String id of the channel to find sockets that are subscribed
      #               example: "issue:5601", "pull_request:1232"
      # data        - Hash to send as JSON to the sockets
      def notify_channel(channel_id, data, authzd_attributes:)
        raise TypeError, "expected data to be a Hash, but was #{data.class}" unless data.is_a?(Hash)
        return unless enabled?
        publish_message(channel_id, data, authzd_attributes)
      end

      # Private: Notify all subscribers for the specific channel about updates
      # regarding 'data', and experiment with getting the authorized channels from
      # authzd.
      #
      # entity      - Entity (e.g a Repository or Team) to scope permissions to
      # channel_id  - the String id of the channel to find sockets that are subscribed
      #               example: "issue:5601", "pull_request:1232"
      # data        - Hash to send as JSON to the sockets
      def notify_entity_channel(entity, channel_id, data, authzd_attributes:)
        notify_channel(channel_id, data, authzd_attributes: authzd_attributes)
      end

      def notify_site_admin_channel(entity, channel_id, data, authzd_attributes:)
        notify_channel(channel_id, data, authzd_attributes: authzd_attributes)
      end

      # Private: Notify all subscribers with write access to the specific
      # repository-related channel about updates regarding 'data', and experiment
      # with getting the authorized channels from authzd.
      #
      # entity      - Entity (e.g a Repository or Team) to scope permissions to
      # channel_id  - the String id of the channel to find sockets that are subscribed
      #               example: "issue:5601", "pull_request:1232"
      # data        - Hash to send as JSON to the sockets
      def notify_repository_writable_channel(entity, channel_id, data, authzd_attributes:)
        notify_channel(channel_id, data, authzd_attributes: authzd_attributes)
      end

      # encrypt_attributes takes attributes and returns a
      # string with the nonce, encrypted data, and auth tag together.
      # This value gets decrypted in Alive.
      def encrypt_attributes(attrs)
        key = GitHub.alive_encryption_key
        nonce = OpenSSL::Random.random_bytes(12)

        aes = OpenSSL::Cipher::AES.new(128, :GCM)
        aes.encrypt
        aes.key = Base64.decode64(key)
        aes.iv = nonce
        aes.auth_data = ""

        encrypted = aes.update(attrs) + aes.final
        tag = aes.auth_tag

        nonce + encrypted + tag
      end
    end
  end
end
