# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class VersionPublishedProcessor < BaseProcessor
        default_to_write_connection!

        include TransientErrorResiliency
        include CommonMethods

        self.slack_pause_notifications_channel = "#billing-alerts"

        DEFAULT_GROUP_ID = "rms_version_published"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.VersionPublished\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 1.megabytes
        options[:start_from_beginning] = false

        # Initialize the IndexVersionPublishedProcessor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
          self.metric_prefix = "register_webhooks_processor"
        end

        # Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          req_context = message.value.dig(:request_context)
          initialize_context(req_context)

          trace_processor(self, req_context) do
            register_webhook(message)
          end
        end

        def register_webhook(message)
          actor_id = get_actor_id(message.value.dig(:actor_id), message.value.dig(:actor_type))
          return unless actor_id.present?
          pkg_subtype = message.value.dig(:pkg_subtype)
          if pkg_subtype.present? && pkg_subtype.is_a?(Enumerable)
            pkg_subtype = pkg_subtype_aop?(pkg_subtype, message, actor_id)
          end
          input = {
            actor_id: actor_id,
            action: :published,
            package: message.value.dig(:package),
            version: message.value.dig(:version),
            package_file: message.value.dig(:file),
            pkg_subtype: pkg_subtype,
          }
          GitHub.instrument("packagev2.create", input.merge({ action: "create" })) # Will be deprecated in favor of `package` event
          GitHub.instrument("package.create", input)
          GitHub.instrument("registry_package.create", input)
        end

        private

        def error_context_for_message(message)
          super(message).merge({
            package_id: message.value.dig(:package, :id),
            namespace: namespace(message),
            name: pkg_name(message),
            version_id: message.value.dig(:version, :id),
            version: message.value.dig(:version, :name),
          })
        end

        def get_actor_id(actor_id, actor_type)
          case actor_type
          when :ACTOR_TYPE_USER
            actor_id
          when :ACTOR_TYPE_INSTALLATION
            IntegrationInstallation.find_by(id: actor_id)&.bot&.id
          when :ACTOR_TYPE_SITE_SCOPED_INSTALLATION
            # In case it is a site scoped installation, we can't use IntegrationInstallation any more. We need to query the SiteScopedIntegrationInstallation instead.
            SiteScopedIntegrationInstallation.find_by(id: actor_id)&.bot&.id
          when :ACTOR_TYPE_UNSPECIFIED
            GitHub.logger.info(
              "Unspecified user type",
              "code.function" =>  __method__,
              "code.namespace" => self.class.name,
              "gh.registry.actor_id" => actor_id,
            )
            nil
          end
        end

        def pkg_subtype_aop?(pkg_subtype, message, actor_id)
          if pkg_subtype[:value] == "actions" || (pkg_subtype[:value] == "sig" && is_aop?(ecosystem(message), namespace(message), pkg_name(message), actor_type(message), actor_id))
            pkg_subtype = "actions"
          end
          pkg_subtype
        end

        def ecosystem(message)
          message.value.dig(:package, :ecosystem)
        end

        def namespace(message)
          message.value.dig(:package, :namespace)
        end

        def pkg_name(message)
          message.value.dig(:package, :name)
        end

        def actor_type(message)
          message.value.dig(:actor_type)
        end

        def is_aop?(ecosystem, namespace, name, actor_type, actor_id)
          client = ::PackageRegistry::Twirp.metadata_client
          latest_non_signature_version = client.get_container_non_sign_latest_version(
            ecosystem: ecosystem,
            namespace: namespace,
            name: name,
            actor_type: get_actor_type_enum(actor_type),
            actor_id: actor_id,
            integration_name: Apps::Privileged::Actions::PACKAGES_AUTHORIZATION_NAME, # we know this is Actions, not Codespaces, because it's a publish processor and Codespaces does not publish.
          )
          latest_non_signature_version&.aop?
        end

        def get_actor_type_enum(actor_type)
          actor_type_rms = 0 #unspecified
          case actor_type
          when :ACTOR_TYPE_USER
            actor_type_rms = Hydro::Schemas::RegistryMetadata::V0::Entities::ActorType::ACTOR_TYPE_USER
          when :ACTOR_TYPE_INSTALLATION
            actor_type_rms = Hydro::Schemas::RegistryMetadata::V0::Entities::ActorType::ACTOR_TYPE_INSTALLATION
          when :ACTOR_TYPE_SITE_SCOPED_INSTALLATION
            actor_type_rms = Hydro::Schemas::RegistryMetadata::V0::Entities::ActorType::ACTOR_TYPE_SITE_SCOPED_INSTALLATION
          when :ACTOR_TYPE_UNSPECIFIED
            actor_type_rms = Hydro::Schemas::RegistryMetadata::V0::Entities::ActorType::ACTOR_TYPE_UNSPECIFIED
          end
          actor_type_rms
        end
      end
    end
  end
end
