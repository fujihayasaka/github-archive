# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-users"

module Api::Internal::Twirp::Copilot
  module Users
    module V1
      # Handler for the MonolithTwirp::Copilot::Users::V1::CopilotUserDetailAPIService
      class CopilotUserDetailAPIHandler < Api::Internal::Twirp::Handler
        include Api::Internal::Twirp::Copilot::Helpers

        # Tenant slugs for the Microsoft-operated Proxima stamps (msft.ghe.com and
        # microsoft.ghe.com). Every user on these stamps is considered staff.
        MICROSOFT_PROXIMA_STAMP_SLUGS = T.let(%w[msft microsoft].freeze, T::Array[String])

        # Slug of the Microsoft enterprise managed users (EMU) enterprise on dotcom.
        MICROSOFT_EMU_ENTERPRISE_SLUG = T.let("microsoft", String)

        sig do
          params(
            rack_env: T::Hash[T.untyped, T.untyped],
            env: T::Hash[T.untyped, T.untyped],
          ).void
        end
        def before_rpc(rack_env, env)
          if (client_key = rack_env[:request_hmac_key])
            env[:client_name] = GitHub.api_internal_twirp_hmac_settings[client_key]
          end
          env[:internal_client_id] = rack_env[:internal_client_id]
          env[:real_ip]            = rack_env["HTTP_X_CLIENT_IP"]
          env[:request_id]         = rack_env["HTTP_X_GITHUB_REQUEST_ID"]
        end

        allow_access_for :client, allowed_clients: %w[
          copilot_api
          copilot_abuse_service
          copilot_activity_service
          copilot_chat
          copilot_mission_control
          copilot_usage_service
          sweagentd
          chat_integrations
          copilot_code_review_agent
        ]
        handles_service MonolithTwirp::Copilot::Users::V1::CopilotUserDetailAPIService

        resolve_tenant_context only: [
          :get_copilot_user,
          :bulk_user_lookup,
          :enable_a_chat,
          :enable_a_f_chat,
          :enable_g_chat,
          :enable_g_t_f,
          :enable_o_f_m,
          :enable_o_t,
          :enable_o_f_o,
          :enable_a_l,
          :enable_a_o_f_o,
          :enable_a_f_o_s,
          :enable_model,
          :enable_registry_model,
          :get_custom_models_details,
        ] do |data, env|
          case env[:rpc_method]
          when :GetCopilotUser
            user = if data.id.present? && data.id.nonzero?
              ::User.find_by(id: data.id)
            elsif data.analytics_tracking_id.present?
              ::User.find_by(analytics_tracking_id: data.analytics_tracking_id)
            else
              nil
            end
          when :EnableAChat
            user = if data.id.present? && data.id.nonzero?
              ::User.find_by(id: data.id)
            elsif data.analytics_tracking_id.present?
              ::User.find_by(analytics_tracking_id: data.analytics_tracking_id)
            else
              nil
            end
          when :EnableAFChat
            user = if data.id.present? && data.id.nonzero?
              ::User.find_by(id: data.id)
            elsif data.analytics_tracking_id.present?
              ::User.find_by(analytics_tracking_id: data.analytics_tracking_id)
            else
              nil
            end
          when :EnableGChat
            user = if data.id.present? && data.id.nonzero?
              ::User.find_by(id: data.id)
            elsif data.analytics_tracking_id.present?
              ::User.find_by(analytics_tracking_id: data.analytics_tracking_id)
            else
              nil
            end
          when :EnableGTF, :EnableOFM, :EnableOT, :EnableOFO, :EnableAL, :EnableAFOS, :EnableGTFF, :EnableModel, :EnableRegistryModel, :GetCustomModelsDetails
            user = if data.id.present? && data.id.nonzero?
              ::User.find_by(id: data.id)
            elsif data.analytics_tracking_id.present?
              ::User.find_by(analytics_tracking_id: data.analytics_tracking_id)
            else
              nil
            end
          when :SubscribeLimitedUser
            user = if data.id.present? && data.id.nonzero?
              ::User.find_by(id: data.id)
            elsif data.analytics_tracking_id.present?
              ::User.find_by(analytics_tracking_id: data.analytics_tracking_id)
            else
              nil
            end
          when :BulkUserLookup
            user = ::User.find_by(analytics_tracking_id: data.analytics_tracking_ids.first)
          else
            user = nil
          end

          next user&.enterprise_managed_business
        end

        # Public: Implementation of the GetCopilotUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Users::V1::GetCopilotUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Users::V1::GetCopilotUserResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::GetCopilotUserRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def get_copilot_user(req, env)
          GitHub.tracer.in_span("copilot.twirp.get_copilot_user", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.get_copilot_user") do
              result = load_user(req)

              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)

              GitHub.logger.info(
                "GetCopilotUser called",
                "gh.user.id" => copilot_user.user_object.id
              )

              load_copilot_user_response(copilot_user, env)
            end
          end
        end

        # Public: Implementation of the BulkUserLookup Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Users::V1::BulkUserLookupRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Users::V1::BulkUserLookupResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::BulkUserLookupRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def bulk_user_lookup(req, env)
          GitHub.tracer.in_span("copilot.twirp.bulk_user_lookup", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.bulk_user_lookup") do
              result = bulk_load_users(req)

              return result.error unless result.ok?

              result.value!
            end
          end
        end

        # Public: Implementation of the SubscribeLimitedUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Users::V1::SubscribeLimitedUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Users::V1::SubscribeLimitedUserResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::SubscribeLimitedUserRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def subscribe_limited_user(req, env)
          GitHub.tracer.in_span("copilot.twirp.subscribe_limited_user", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.subscribe_limited_user") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)

              # subscribe them to the limited user sku
              subscribed = copilot_user.subscribe_limited_user

              GitHub.logger.info(
                "Limited user attempted to subscribe",
                "gh.user.id" => copilot_user.user_object.id,
                "gh.copilot.limited_user.subscribed" => subscribed.ok?,
              )

              if subscribed.ok?
                Copilot::Instrumenter.instrument_signup_limited_subscription_created(
                  copilot_user,
                  utm_query_params: {
                    utm_medium: "Twirp",
                    },
                )
                # We want to run this async so it's guaranteed to return value if another query is made
                copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "signup_free") if subscribed.ok?
                Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.for(copilot_user.user_object))
              end

              return { success: subscribed.ok? }
            end
          end
        end

        # Public: Implementation of the EnableAChat Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Users::V1::EnableAChatRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Users::V1::EnableAChatResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableAChatRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_a_chat(req, env)
          # DataDog shows that this span is never hit, remove it after copilot-twirp is updated
          GitHub.tracer.in_span("copilot.twirp.enable_a_chat", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_a_chat") do
              return { success: false }
            end
          end
        end

        # Public: Implementation of the EnableAFChat Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Users::V1::EnableAFChatRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Users::V1::EnableAFChatResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableAFChatRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_a_f_chat(req, env)
          # DataDog shows this span is never hit
          GitHub.tracer.in_span("copilot.twirp.enable_a_f_chat", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_a_f_chat") do
              return { success: false }
            end
          end
        end

        # Public: Implementation of the EnableGChat Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Users::V1::EnableGChatRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Users::V1::EnableGChatResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableGChatRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_g_chat(req, env)
          # DataDog shows that this span is never hit, remove it after copilot-twirp is updated
          GitHub.tracer.in_span("copilot.twirp.enable_g_chat", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_g_chat") do
              return { success: false }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableGTFRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_g_t_f(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_g_tf", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_g_tf") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)

              GitHub.logger.info(
                "EnableGTF called",
                "gh.user.id" => copilot_user.user_object.id
              )

              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.g_tf_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "inline_enablement")
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableOFMRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_o_f_m(req, env)
          # DataDog shows that this span is never hit, remove it after copilot-twirp is updated
          GitHub.tracer.in_span("copilot.twirp.enable_o_f_m", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_o_f_m") do
              return { success: false }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableOTRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_o_t(req, env)
          # DataDog shows that this span is never hit, remove it after copilot-twirp is updated
          GitHub.tracer.in_span("copilot.twirp.enable_o_t", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_o_t") do
              return { success: false }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableOFORequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_o_f_o(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_o_f_o", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_o_f_o") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)

              GitHub.logger.info(
                "EnableOFO called",
                "gh.user.id" => copilot_user.user_object.id
              )

              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.ofo_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "inline_enablement")
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableALRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_a_l(req, env)
          # DataDog shows that this span is never hit, remove it after copilot-twirp is updated
          GitHub.tracer.in_span("copilot.twirp.enable_a_l", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_a_l") do
              return { success: false }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableAOFORequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_a_o_f_o(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_a_o_f_o", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_a_o_f_o") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)

              GitHub.logger.info(
                "EnableAOFO called",
                "gh.user.id" => copilot_user.user_object.id
              )

              return { success: false } unless Copilot::Users::ModelAccess.model_available?(copilot_user, :aofo)
              copilot_user.aofo_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "inline_enablement")
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableAFOSRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_a_f_o_s(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_a_f_o_s", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_a_f_o_s") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)

              GitHub.logger.info(
                "EnableAFOS called",
                "gh.user.id" => copilot_user.user_object.id
              )

              return { success: false } unless Copilot::Users::ModelAccess.model_available?(copilot_user, :afos)
              copilot_user.afos_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "inline_enablement")
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableGTFFRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_g_t_f_f(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_g_t_f_f", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_g_t_f_f") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)
              return { success: false } unless Copilot::Users::ModelAccess.model_available?(copilot_user, :gtff)
              copilot_user.gtff_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "inline_enablement")
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableModelRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_model(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_model", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_model") do
              result = load_user(req)
              model_name = T.unsafe(req).model_name
              return result.error unless result.ok?

              copilot_user = T.unsafe(Copilot::User.new(result.value!))

              GitHub.logger.with_named_tags({ "gh.user.id" => copilot_user.user_object.id, "gh.copilot.model" => model_name }) do
                GitHub.logger.info("EnableModel called")

                return { success: false } unless model_name.present?

                model = Copilot::Policies::MODELS.find { |m| m.config_name == model_name }
                return { success: false } unless model && model.available_for?(copilot_user) && copilot_user.has_cfi_access?
                model.update_user(copilot_user, "enabled")

                # We want to run this async so it's guaranteed to return value if another query is made
                copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "inline_enablement")

                GitHub.logger.info("EnableModel completed")

                return { success: true }
              end
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableRegistryModelRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def enable_registry_model(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_model", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_model") do
              result = load_user(req)
              model_key = T.unsafe(req).model_key
              return result.error unless result.ok?
              return { success: false } unless model_key.present?

              copilot_user = T.unsafe(Copilot::User.new(result.value!))
              return { success: false } unless copilot_user.has_cfi_access?
              # find if the model exists in the registry cache
              available_models = copilot_user.registry_models

              return { success: false } unless available_models.any? { |m| m.model_key == model_key }

              copilot_user.update_model_configuration!(model_key, "enabled")

              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "inline_enablement")

              GitHub.logger.info(
                "EnableRegistryModel called",
                "gh.user.id" => copilot_user.user_object.id,
                "gh.copilot.model.enabled" => model_key,
              )

              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::GetCustomModelsDetailsRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
             T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def get_custom_models_details(req, env)
          GitHub.tracer.in_span("copilot.twirp.get_custom_models_details", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.get_custom_models_details") do
              result = load_user(req)
              return result.error unless result.ok?
              user = T.let(result.value!, ::User)

              return Twirp::Error.invalid_argument("key_id must be provided") if req.key_id.empty?
              return Twirp::Error.invalid_argument("model_slug must be provided") if req.model_slug.empty?

              custom_key = CopilotByok::CustomKey.for_user(user).find_by(id: req.key_id)
              return Twirp::Error.not_found("Custom Key '#{req.key_id}' not found.") if custom_key.nil?

              custom_model = custom_key.custom_models.find_by(slug: req.model_slug)
              return Twirp::Error.not_found("Custom Model '#{req.model_slug}' not found.") if custom_model.nil?

              encrypted_secret_value = custom_key.encrypted_secret_value
              return Twirp::Error.internal("Failed getting secret value") if encrypted_secret_value.nil?

              # As defined in https://github.com/github/copilot-twirp/blob/91f411b07b914232c93c82e069467942a471fc36/proto/users/v1/byok.proto#L78
              result = { encrypted_secret_value: encrypted_secret_value }

              if custom_key.azureai?
                result[:azureai] = { deployment_url: custom_key.deployment_url }
              elsif custom_key.awsbedrock?
                provider_data = custom_model.provider_data&.to_twirp_details
                result[:awsbedrock] = provider_data.symbolize_keys if provider_data.present?
              elsif custom_key.openaicompatible?
                provider_data = custom_key.provider_data&.to_twirp_details
                result[:openaicompatible] = provider_data.symbolize_keys if provider_data.present?
              end

              result
            end
          end
        end

        private

        CopilotAChatResponse = T.type_alias do
          {
            success: T::Boolean
          }
        end

        CopilotGChatResponse = T.type_alias do
          {
            success: T::Boolean
          }
        end

        CopilotUserDetails = T.type_alias do
          {
            a_chat_setting: T.nilable(T.any(Symbol, Integer)),
            billing_enterprise_id: T.nilable(Integer),
            billing_entity_resolved: T::Boolean,
            billing_organization_id: T.nilable(Integer),
            administrative_blocked: T.nilable(T::Boolean),
            af_setting: T.nilable(T.any(Symbol, Integer)),
            afos_setting: T.nilable(T.any(Symbol, Integer)),
            agent_mode: T.nilable(T.any(Symbol, Integer)),
            antman_setting: T.nilable(T.any(Symbol, Integer)),
            al_setting: T.nilable(T.any(Symbol, Integer)),
            analytics_tracking_id: T.nilable(String),
            aofo_setting: T.nilable(T.any(Symbol, Integer)),
            arcticfox_setting: T.nilable(T.any(Symbol, Integer)),
            auto_approve_agent_mode_setting: T.nilable(T.any(Symbol, Integer)),
            automatic_code_review_setting: T.nilable(T.any(Symbol, Integer)),
            bento_setting: T.nilable(T.any(Symbol, Integer)),
            bing_setting: T.nilable(T.any(Symbol, Integer)),
            blackbird_external_indexing_setting: T.nilable(T.any(Symbol, Integer)),
            model_native_search_setting: T.nilable(T.any(Symbol, Integer)),
            blackpanther_setting: T.nilable(T.any(Symbol, Integer)),
            blueberry_setting: T.nilable(T.any(Symbol, Integer)),
            captainamerica_setting: T.nilable(T.any(Symbol, Integer)),
            cca_direct_org_billing_setting: T.nilable(T.any(Symbol, Integer)),
            ccr_direct_org_billing_setting: T.nilable(T.any(Symbol, Integer)),
            cherry_setting: T.nilable(T.any(Symbol, Integer)),
            cli_cloud_session_storage_setting: T.nilable(T.any(Symbol, Integer)),
            cli_remote_control_setting: T.nilable(T.any(Symbol, Integer)),
            cli_setting: T.nilable(T.any(Symbol, Integer)),
            client_byok_setting: T.nilable(T.any(Symbol, Integer)),
            code_review_beta_features_setting: T.nilable(T.any(Symbol, Integer)),
            code_review_setting: T.nilable(T.any(Symbol, Integer)),
            content_exclusion_enabled: T.nilable(T::Boolean),
            copilot_access_type: T.nilable(T.any(Symbol, Integer)),
            copilot_beta_features_opt_in_setting: T.nilable(T.any(Symbol, Integer)),
            copilot_organizations: T::Array[MonolithTwirp::Copilot::Users::V1::CopilotOrganization],
            enterprise_memberships: T.nilable(T::Array[MonolithTwirp::Copilot::Users::V1::EnterpriseMembership]),
            copilot_plan: T.nilable(T.any(Symbol, Integer)),
            country_code: T.nilable(String),
            cucumber_setting: T.nilable(T.any(Symbol, Integer)),
            custom_model: T.nilable(T.any(Symbol, Integer)),
            custom_models: T.nilable(T::Array[MonolithTwirp::Copilot::Users::V1::BYOKCustomModel]),
            daisy_setting: T.nilable(T.any(Symbol, Integer)),
            desktop_setting: T.nilable(T.any(Symbol, Integer)),
            dotcom_chat_setting: T.nilable(T.any(Symbol, Integer)),
            editor_chat_setting: T.nilable(T.any(Symbol, Integer)),
            editor_preview_features_setting: T.nilable(T.any(Symbol, Integer)),
            experimental_auto_models_setting: T.nilable(T.any(Symbol, Integer)),
            g_chat_setting: T.nilable(T.any(Symbol, Integer)),
            grok_code_setting: T.nilable(T.any(Symbol, Integer)),
            gtf_setting: T.nilable(T.any(Symbol, Integer)),
            gtff_setting: T.nilable(T.any(Symbol, Integer)),
            has_cfb_access: T.nilable(T::Boolean),
            has_cfe_access: T.nilable(T::Boolean),
            has_cfi_access: T.nilable(T::Boolean),
            has_country_code: T.nilable(T::Boolean),
            has_free_access: T.nilable(T::Boolean),
            has_limited_access: T.nilable(T::Boolean),
            has_paid_access: T.nilable(T::Boolean),
            hulk_setting: T.nilable(T.any(Symbol, Integer)),
            id: T.nilable(Integer),
            is_ccr_globally_blocked: T.nilable(T::Boolean),
            is_partner_user:  T.nilable(T::Boolean),
            is_model_picker_enabled: T.nilable(T::Boolean),
            is_staff: T.nilable(T::Boolean),
            is_trade_restricted: T.nilable(T::Boolean),
            use_token_based_billing: T.nilable(T::Boolean),
            lotus_setting: T.nilable(T.any(Symbol, Integer)),
            m_ironman_setting: T.nilable(T.any(Symbol, Integer)),
            m_spiderman_setting: T.nilable(T.any(Symbol, Integer)),
            m_thor_setting: T.nilable(T.any(Symbol, Integer)),
            mcp: T.nilable(T.any(Symbol, Integer)),
            memory_setting: T.nilable(T.any(Symbol, Integer)),
            mobile_chat_setting: T.nilable(T.any(Symbol, Integer)),
            model_policies: T.nilable(T::Hash[String, Integer]),
            o1_setting: T.nilable(T.any(Symbol, Integer)),
            o3_setting: T.nilable(T.any(Symbol, Integer)),
            obmb_setting: T.nilable(T.any(Symbol, Integer)),
            obmw_setting: T.nilable(T.any(Symbol, Integer)),
            of_setting: T.nilable(T.any(Symbol, Integer)),
            ofct_setting: T.nilable(T.any(Symbol, Integer)),
            off_setting: T.nilable(T.any(Symbol, Integer)),
            ofm_setting: T.nilable(T.any(Symbol, Integer)),
            ofo_setting: T.nilable(T.any(Symbol, Integer)),
            ot_setting: T.nilable(T.any(Symbol, Integer)),
            peony_setting: T.nilable(T.any(Symbol, Integer)),
            pr_summarization: T.nilable(T.any(Symbol, Integer)),
            private_docs: T.nilable(T.any(Symbol, Integer)),
            restrict_to_azure_setting: T.nilable(T.any(Symbol, Integer)),
            restrict_to_data_residency_setting: T.nilable(T.any(Symbol, Integer)),
            restrict_to_fedramp_setting: T.nilable(T.any(Symbol, Integer)),
            skuisolation: T.nilable(SKUIsolation),
            snippy_setting: T.nilable(T.any(Symbol, Integer)),
            duplicate_detection_filter_setting: T.nilable(T.any(Symbol, Integer)),
            spaces_individual_access_setting: T.nilable(T.any(Symbol, Integer)),
            spaces_individual_sharing_setting: T.nilable(T.any(Symbol, Integer)),
            spaces_setting: T.nilable(T.any(Symbol, Integer)),
            spammy: T.nilable(T::Boolean),
            sunflower_setting: T.nilable(T.any(Symbol, Integer)),
            swe_agent_setting: T.nilable(T.any(Symbol, Integer)),
            telemetry_configuration: T.nilable(T.any(Symbol, Integer)),
            trust_tier: T.nilable(T.any(Symbol, Integer)),
            tulip_setting: T.nilable(T.any(Symbol, Integer)),
            watermelon_setting: T.nilable(T.any(Symbol, Integer)),
            wintersoldier_setting: T.nilable(T.any(Symbol, Integer)),
          }
        end

        SKUIsolation = T.type_alias do
          {
            api_host: String,
          }
        end

        GetCopilotUserResponse = T.type_alias do
          {
            user_details: T.nilable(CopilotUserDetails)
          }
        end

        BulkUserDetail = T.type_alias do
          {
            analytics_tracking_id: T.nilable(String),
            copilot_access_type: T.nilable(T.any(Symbol, Integer)),
            copilot_organizations: T.nilable(T.any(Google::Protobuf::RepeatedField[MonolithTwirp::Copilot::Users::V1::CopilotOrganization], T::Array[MonolithTwirp::Copilot::Users::V1::CopilotOrganization])),
            copilot_seat_ids: T.nilable(T.any(Google::Protobuf::RepeatedField[Integer], T::Array[Integer])),
            created_at: T.nilable(Google::Protobuf::Timestamp),
            display_login: T.nilable(String),
            id: T.nilable(Integer),
            spammy: T.nilable(T::Boolean),
            suspended: T.nilable(T::Boolean),
            time_zone_name: T.nilable(String)
          }
        end

        sig { params(req: MonolithTwirp::Copilot::Users::V1::BulkUserLookupRequest).returns(GitHub::Result) }
        def bulk_load_users(req)
          GitHub.tracer.in_span("copilot.twirp.bulk_load_users", kind: :internal) do
            if req.analytics_tracking_ids.empty?
              GitHub::Result.error(Twirp::Error.invalid_argument("must be provided", argument: "analytics_tracking_ids"))
            else
              bulk_user_details = Set.new # using a set makes sure we don't duplicate users

              req.analytics_tracking_ids.map(&:to_s).in_groups_of(100, false) do |batch_scope|
                users = ::User.where(analytics_tracking_id: batch_scope)
                user_ids = users.pluck(:id)
                seats = Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: user_ids).inject(Hash.new) do |acc, seat|
                  acc[seat.assigned_user_id] = Hash.new unless acc.key?(seat.assigned_user_id)
                  acc[seat.assigned_user_id][:seat_ids] = [] unless acc[seat.assigned_user_id].key?(:seat_ids)
                  acc[seat.assigned_user_id][:seat_ids] << seat.id

                  if seat.seat_assignment.present? && T.must(seat.seat_assignment).owner_type == "Organization"
                    acc[seat.assigned_user_id][:organizations] = [] unless acc[seat.assigned_user_id].key?(:organizations)
                    acc[seat.assigned_user_id][:organizations] << {
                      id: T.must(seat.seat_assignment).owner_id,
                      analytics_tracking_id: seat.seat_assignment&.owner.analytics_tracking_id
                    }
                  end
                  acc
                end

                users.each do |user|
                  seat = seats[user.id]
                  copilot_organizations = seat.present? ? seat.fetch(:organizations, []) : []
                  seat_ids = seat.present? ? seat.fetch(:seat_ids, []) : []

                  bulk_user_details << {
                    analytics_tracking_id: user.analytics_tracking_id,
                    copilot_access_type: twirp_access_type(Copilot::User.new(user).access_type),
                    copilot_organizations: copilot_organizations.map do |copilot_organization|
                      MonolithTwirp::Copilot::Users::V1::CopilotOrganization.new({
                        id: copilot_organization[:id],
                        analytics_tracking_id: copilot_organization[:analytics_tracking_id],
                      })
                    end,
                    copilot_seat_ids: seat_ids,
                    created_at: Google::Protobuf::Timestamp.new(seconds: user.created_at.to_i, nanos: 0),
                    display_login: user.display_login,
                    id: user.id,
                    spammy: user.spammy?,
                    suspended: user.suspended?,
                    time_zone_name: user.time_zone_name,
                  }
                end
              end

              GitHub::Result.new do
                {
                  bulk_user_details: bulk_user_details.to_a,
                }
              end
            end
          end
        end

        sig { params(req: T.untyped).returns(GitHub::Result) }
        def load_user(req)
          GitHub.tracer.in_span("copilot.twirp.load_user", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.load_user") do
              if req.id.present? && req.id.nonzero?
                # they passed that id
                user = ::User.find_by(id: req.id)
                return GitHub::Result.new { user } if user

                GitHub.dogstats.increment("copilot.twirp.user_not_found")
                GitHub::Result.error(Twirp::Error.not_found("User ID '#{req.id}' not found."))
              elsif req.analytics_tracking_id.present?
                # they passed the analytics tracking id
                user = ::User.find_by(analytics_tracking_id: req.analytics_tracking_id)
                return GitHub::Result.new { user } if user

                GitHub.dogstats.increment("copilot.twirp.user_not_found")
                GitHub::Result.error(Twirp::Error.not_found("User Analytics ID '#{req.analytics_tracking_id}' not found."))
              else
                # they didn't pass either
                GitHub.dogstats.increment("copilot.twirp.no_params")
                GitHub::Result.error(Twirp::Error.invalid_argument("must be provided", argument: "id or analytics_tracking_id"))
              end
            end
          end
        end

        sig do
          params(
            copilot_user: Copilot::User,
            env: T::Hash[T.untyped, T.untyped]
          ).
          returns(
            GetCopilotUserResponse
          )
        end
        def load_copilot_user_response(copilot_user, env)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_user_response", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.load_copilot_user_response") do
              auth = copilot_user.copilot_authorizer_object_no_snippy
              access_type = load_access_type(auth)

              if copilot_user.organizations.any? { |o| o.feature_flag_enabled?(:copilot_disable_all_access_for_org_members, default: false) }
                # this creates a conflict between the checks for individual fields below and the access type
                # with the intention that this is a stopgap measure to block all copilot access for users of a given org
                GitHub.logger.info(
                  "User access blocked due to copilot_disable_all_access_for_org_members feature flag",
                  "gh.user.id" => copilot_user.user_object.id,
                )
                access_type = MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_INVALID
              end

              if auth.has_cfb_access? || auth.has_cfe_access?
                GitHub.logger.info(
                  "Instrumenting token generated",
                  "gh.user.id" => copilot_user.user_object.id,
                  "gh.copilot.access_type" => auth.access_type,
                )

                Copilot::Instrumenter.instrument_token_generated(
                  copilot_user,
                  -1,
                  auth.access_type,
                  {
                    request_id: env[:request_id],
                    client_name: env[:client_name],
                    real_ip: env[:real_ip],
                    internal_client_id: env[:internal_client_id],
                  },
                  auth.organization_list,
                  source: "twirp_copilot_user_detail",
                )
              end

              {
                user_details: Copilot::Policies.twirp_user_settings(copilot_user).merge({
                  administrative_blocked: copilot_user.administrative_blocked?,
                  analytics_tracking_id: copilot_user.user_object.analytics_tracking_id,
                  content_exclusion_enabled: copilot_user.copilot_content_exclusion_enabled?,
                  copilot_access_type: access_type,
                  copilot_organizations: load_organization_details(copilot_user),
                  enterprise_memberships: load_enterprise_memberships(copilot_user),
                  **load_active_billing_entity(copilot_user),
                  copilot_plan: load_copilot_plan(copilot_user, access_type),
                  country_code: copilot_user.country_code,
                  custom_models: load_custom_models(copilot_user),
                  has_cfb_access: auth.has_cfb_access?,
                  has_cfe_access: auth.has_cfe_access?,
                  has_cfi_access: auth.has_cfi_access?,
                  has_country_code: copilot_user.country_code.nil?,
                  has_free_access: auth.access_type != :NO_ACCESS && !auth.has_paid_access?,
                  has_limited_access: auth.has_limited_access?,
                  has_paid_access: auth.has_paid_access?,
                  id: copilot_user.id,
                  is_ccr_globally_blocked: copilot_user.ccr_globally_blocked?,
                  is_partner_user: copilot_user.is_partner_user?,
                  is_model_picker_enabled: copilot_user.has_o1_models_access?,
                  is_staff: staff?(copilot_user),
                  is_trade_restricted: copilot_user.trade_restricted?,
                  use_token_based_billing: copilot_user.use_token_based_billing?,
                  skuisolation: load_copilot_sku_isolation(copilot_user, client_name: env[:client_name]),
                  spammy: copilot_user.spammy?,
                  telemetry_configuration: load_telemetry(copilot_user),
                  trust_tier: load_trust_tier(copilot_user),
                  # TODO: remove these when the Twirp proto no longer expects them
                  of_setting: MonolithTwirp::Copilot::Users::V1::OF::OF_INVALID,
                  af_setting: MonolithTwirp::Copilot::Users::V1::AF::AF_INVALID,
                  g_chat_setting: MonolithTwirp::Copilot::Users::V1::GChat::G_CHAT_INVALID,
                  al_setting: MonolithTwirp::Copilot::Users::V1::AL::AL_INVALID,
                  ot_setting: MonolithTwirp::Copilot::Users::V1::OT::OT_INVALID,
                  ofm_setting: MonolithTwirp::Copilot::Users::V1::OFM::OFM_INVALID,
                  o3_setting: MonolithTwirp::Copilot::Users::V1::O3::O3_INVALID,
                  a_chat_setting: MonolithTwirp::Copilot::Users::V1::AChat::A_CHAT_INVALID,
                })
              }
            end
          end
        end

        sig { params(copilot_user: Copilot::User, client_name: String).returns(T.nilable(SKUIsolation)) }
        def load_copilot_sku_isolation(copilot_user, client_name: "")
          if copilot_user.feature_flag_enabled?(:copilot_sku_isolation_use_public_user_perf, default: false)
            # TODO - roll this out by each different client.
            sku_isolation = Copilot::SKUIsolation.for_user(copilot_user.user_object, public_user_enabled: true)
            GitHub.logger.info(
              "Getting SKU Isolation in Twirp with Public User",
              "gh.user.id" => copilot_user.user_object.id,
              "gh.copilot.sku_isolation.api_host" => sku_isolation.api.host,
            )
          else
            sku_isolation = Copilot::SKUIsolation.new(copilot_user, GitHub::CurrentTenant.get)
          end

          return unless sku_isolation.enforce_api?

          {
            api_host: sku_isolation.api.host,
          }
        end

        sig { params(copilot_user: Copilot::User, access_type: Integer).returns(Integer) }
        def load_copilot_plan(copilot_user, access_type)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_plan", kind: :internal) do
            if access_type == MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_INVALID
              return MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_INVALID
            end

            case copilot_user.copilot_plan.downcase
            when "individual"
              return MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_INDIVIDUAL_PRO if copilot_user.has_pro_plus_access?
              return MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_INDIVIDUAL_MAX if copilot_user.has_max_access?
              return MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_INDIVIDUAL_EDU if copilot_user.has_educational_access? && copilot_user.feature_flag_enabled?(:copilot_twirp_individual_edu_plan, default: false)

              MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_INDIVIDUAL
            when "enterprise"
              MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_ENTERPRISE
            when "business"
              MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_BUSINESS
            else
              MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_INVALID
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_telemetry(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_telemetry", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::Telemetry::TELEMETRY_ENABLED if copilot_user.telemetry_enabled?
            MonolithTwirp::Copilot::Users::V1::Telemetry::TELEMETRY_DISABLED
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_trust_tier(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_trust_tier", kind: :internal) do
            case copilot_user.trust_tier
            when :TRUST_TIER_UNTRUSTED
              MonolithTwirp::Copilot::Users::V1::TrustTier::TRUST_TIER_UNTRUSTED
            when :TRUST_TIER_NEUTRAL
              MonolithTwirp::Copilot::Users::V1::TrustTier::TRUST_TIER_NEUTRAL
            when :TRUST_TIER_TRUSTED
              MonolithTwirp::Copilot::Users::V1::TrustTier::TRUST_TIER_TRUSTED
            else
              MonolithTwirp::Copilot::Users::V1::TrustTier::TRUST_TIER_INVALID
            end
          end
        end

        sig { params(auth: Copilot::Authorizer).returns(Integer) }
        def load_access_type(auth)
          GitHub.tracer.in_span("copilot.twirp.load_access_type", kind: :internal) do
            if auth.access_type.to_s.include?("SEAT_ASSIGNMENT")
              GitHub.logger.info("Triggering seat assignment conversion", "gh.user.id" => auth.copilot_user.user_object.id)
              Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_later(
                user_id: auth.copilot_user.user_object.id
              )
            end
            twirp_access_type(auth.access_type)
          end
        end

        sig { params(copilot_user: Copilot::User).returns(T::Array[MonolithTwirp::Copilot::Users::V1::CopilotOrganization]) }
        def load_organization_details(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_organization_details", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.load_organization_details") do
              copilot_user.copilot_organizations.map do |organization|
                MonolithTwirp::Copilot::Users::V1::CopilotOrganization.new({
                  id: organization.id,
                  analytics_tracking_id: organization.analytics_tracking_id,
                })
              end.compact
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(T::Array[MonolithTwirp::Copilot::Users::V1::EnterpriseMembership]) }
        def load_enterprise_memberships(copilot_user)
          # Use Copilot::Public::User to read business_ids directly from the copilot settings cache
          # This avoids additional database queries
          public_user = Copilot::Public::User.for(copilot_user.user_object)
          public_user.business_ids.map do |business_id|
            MonolithTwirp::Copilot::Users::V1::EnterpriseMembership.new({
              enterprise_id: business_id,
            })
          end
        end

        # Resolves the user's active billing entity (organization and enterprise) based on
        # their billable_customer_id selection. For single-SKU users, this is their only
        # copilot provider. For multi-SKU users, this is the entity they selected at
        # /settings/copilot/features. Returns nil values if unresolvable (CfI or multi-SKU without selection).
        sig { params(copilot_user: Copilot::User).returns(T::Hash[Symbol, T.any(T.nilable(Integer), T::Boolean)]) }
        def load_active_billing_entity(copilot_user)
          resolver = Copilot::BillingEntityResolver.new(copilot_user)
          result = resolver.resolve

          billing_entity_resolved = if copilot_user.has_multi_access?
            result.organization.present? || result.business.present?
          else
            true
          end

          {
            billing_organization_id: result.organization&.id,
            billing_enterprise_id: result.business&.id,
            billing_entity_resolved: billing_entity_resolved,
          }
        end

        # Whether the user should be treated as GitHub/Microsoft staff. True when the user is:
        #   * a GitHub employee (the github enterprise / @github/employees team) on dotcom, ignoring
        #     the "disable employee mode" footer override so the flag reflects real staff status, or
        #   * a member of the Microsoft enterprise managed users (EMU) enterprise on dotcom, or
        #   * on one of the Microsoft-operated Proxima stamps (msft.ghe.com / microsoft.ghe.com).
        sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
        def staff?(copilot_user)
          user = copilot_user.user_object

          if GitHub.multi_tenant_enterprise?
            return MICROSOFT_PROXIMA_STAMP_SLUGS.include?(GitHub::CurrentTenant.get&.slug)
          end

          return true if user.employee_ignoring_override?

          user.is_enterprise_managed? && user.enterprise_managed_business&.slug == MICROSOFT_EMU_ENTERPRISE_SLUG
        end

        sig { params(copilot_user: Copilot::User).returns(T::Array[MonolithTwirp::Copilot::Users::V1::BYOKCustomModel]) }
        def load_custom_models(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_custom_models", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.load_custom_models") do
              copilot_user.byok_custom_models.map(&:to_twirp_user_detail)
            end
          end
        end
      end
    end
  end
end
