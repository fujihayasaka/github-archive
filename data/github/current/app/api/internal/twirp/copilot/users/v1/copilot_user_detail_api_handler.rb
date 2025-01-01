# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-users"

module Api::Internal::Twirp::Copilot
  module Users
    module V1
      # Handler for the MonolithTwirp::Copilot::Users::V1::CopilotUserDetailAPIService
      class CopilotUserDetailAPIHandler < Api::Internal::Twirp::Handler

        include Api::Internal::Twirp::Copilot::Helpers

        sig do
          params(
            rack_env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
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
          copilot_usage_service
          sweagentd
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
          :enable_a_f_o_s
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
          when :EnableGTF, :EnableOFM, :EnableOT, :EnableOFO, :EnableAL, :EnableAFOS, :EnableGTFF
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
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
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
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
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
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
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
                copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION) if subscribed.ok?
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
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def enable_a_chat(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_a_chat", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_a_chat") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)
              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.a_chat_enabled!
              # We want to run this async so it's garunteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
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
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def enable_a_f_chat(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_a_f_chat", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_a_f_chat") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)
              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.a_f_enabled!
              # We want to run this async so it's garunteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
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
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def enable_g_chat(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_g_chat", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_g_chat") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)
              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.g_chat_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableGTFRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
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
              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.g_tf_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableOFMRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def enable_o_f_m(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_o_f_m", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_o_f_m") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)
              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.o_fm_enabled!
              # We want to run this async  so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableOTRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def enable_o_t(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_o_t", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_o_t") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)
              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.o_t_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableOFORequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
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
              return { success: false } unless copilot_user.has_cfi_access?
              copilot_user.ofo_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableALRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def enable_a_l(req, env)
          GitHub.tracer.in_span("copilot.twirp.enable_a_l", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.enable_a_l") do
              result = load_user(req)
              return result.error unless result.ok?

              copilot_user = Copilot::User.new(result.value!)
              return { success: false } unless Copilot::Users::ModelAccess.model_available?(copilot_user, :al)
              copilot_user.al_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableAFOSRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
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
              return { success: false } unless Copilot::Users::ModelAccess.model_available?(copilot_user, :afos)
              copilot_user.afos_enabled!
              # We want to run this async so it's guaranteed to return value if another query is made
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
            end
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Users::V1::EnableGTFFRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
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
              copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
              return { success: true }
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
            administrative_blocked: T.nilable(T::Boolean),
            af_setting: T.nilable(T.any(Symbol, Integer)),
            afos_setting: T.nilable(T.any(Symbol, Integer)),
            al_setting: T.nilable(T.any(Symbol, Integer)),
            analytics_tracking_id: T.nilable(String),
            bing_setting: T.nilable(T.any(Symbol, Integer)),
            cli_setting: T.nilable(T.any(Symbol, Integer)),
            desktop_setting: T.nilable(T.any(Symbol, Integer)),
            content_exclusion_enabled: T.nilable(T::Boolean),
            copilot_access_type: T.nilable(T.any(Symbol, Integer)),
            copilot_beta_features_opt_in_setting: T.nilable(T.any(Symbol, Integer)),
            copilot_organizations: T::Array[MonolithTwirp::Copilot::Users::V1::CopilotOrganization],
            copilot_plan: T.nilable(T.any(Symbol, Integer)),
            custom_model: T.nilable(T.any(Symbol, Integer)),
            dotcom_chat_setting: T.nilable(T.any(Symbol, Integer)),
            editor_chat_setting: T.nilable(T.any(Symbol, Integer)),
            editor_preview_features_setting: T.nilable(T.any(Symbol, Integer)),
            automatic_code_review_setting: T.nilable(T.any(Symbol, Integer)),
            g_chat_setting: T.nilable(T.any(Symbol, Integer)),
            gtf_setting: T.nilable(T.any(Symbol, Integer)),
            gtff_setting: T.nilable(T.any(Symbol, Integer)),
            has_cfb_access: T.nilable(T::Boolean),
            has_cfe_access: T.nilable(T::Boolean),
            has_cfi_access: T.nilable(T::Boolean),
            has_free_access: T.nilable(T::Boolean),
            has_limited_access: T.nilable(T::Boolean),
            has_paid_access: T.nilable(T::Boolean),
            id: T.nilable(Integer),
            is_model_picker_enabled: T.nilable(T::Boolean),
            limited_user_quotas: T::Array[MonolithTwirp::Copilot::Users::V1::LimitedUserQuota],
            limited_user_reset_date: T.nilable(MonolithTwirp::Copilot::Users::V1::ResetDate),
            mcp: T.nilable(T.any(Symbol, Integer)),
            mobile_chat_setting: T.nilable(T.any(Symbol, Integer)),
            o1_setting: T.nilable(T.any(Symbol, Integer)),
            o3_setting: T.nilable(T.any(Symbol, Integer)),
            of_setting: T.nilable(T.any(Symbol, Integer)),
            off_setting: T.nilable(T.any(Symbol, Integer)),
            ofm_setting: T.nilable(T.any(Symbol, Integer)),
            ofo_setting: T.nilable(T.any(Symbol, Integer)),
            ot_setting: T.nilable(T.any(Symbol, Integer)),
            pr_summarization: T.nilable(T.any(Symbol, Integer)),
            private_docs: T.nilable(T.any(Symbol, Integer)),
            skuisolation: T.nilable(SKUIsolation),
            snippy_setting: T.nilable(T.any(Symbol, Integer)),
            swe_agent_setting: T.nilable(T.any(Symbol, Integer)),
            spammy: T.nilable(T::Boolean),
            telemetry_configuration: T.nilable(T.any(Symbol, Integer)),
            trust_tier: T.nilable(T.any(Symbol, Integer))
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
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
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

              if copilot_user.organizations.any? { |o| o.feature_enabled?(:copilot_disable_all_access_for_org_members) }
                # this creates a conflict between the checks for individual fields below and the access type
                # with the intention that this is a stopgap measure to block all copilot access for users of a given org
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
                user_details: {
                  a_chat_setting: load_copilot_a_chat_setting(copilot_user),
                  administrative_blocked: copilot_user.administrative_blocked?,
                  af_setting: load_copilot_af_setting(copilot_user),
                  afos_setting: load_copilot_afos_setting(copilot_user),
                  al_setting: load_copilot_al_setting(copilot_user),
                  analytics_tracking_id: copilot_user.user_object.analytics_tracking_id,
                  bing_setting: load_copilot_bing_setting(copilot_user),
                  cli_setting: load_copilot_cli_setting(copilot_user),
                  desktop_setting: load_desktop(copilot_user),
                  content_exclusion_enabled: copilot_user.copilot_content_exclusion_enabled?,
                  copilot_access_type: access_type,
                  copilot_beta_features_opt_in_setting: load_copilot_beta_features_opt_in_setting(copilot_user),
                  copilot_organizations: load_organization_details(copilot_user),
                  copilot_plan: load_copilot_plan(copilot_user, access_type),
                  custom_model: load_copilot_custom_model(copilot_user),
                  dotcom_chat_setting: load_copilot_dotcom_chat_setting(copilot_user),
                  editor_chat_setting: load_copilot_editor_chat_setting(copilot_user),
                  editor_preview_features_setting: load_copilot_editor_preview_features_setting(copilot_user),
                  automatic_code_review_setting: load_copilot_automatic_code_review_setting(copilot_user),
                  g_chat_setting: load_copilot_g_chat_setting(copilot_user),
                  gtf_setting: load_copilot_gtf_setting(copilot_user),
                  gtff_setting: load_copilot_gtff_setting(copilot_user),
                  has_cfb_access: auth.has_cfb_access?,
                  has_cfe_access: auth.has_cfe_access?,
                  has_cfi_access: auth.has_cfi_access?,
                  has_free_access: auth.access_type != :NO_ACCESS && !auth.has_paid_access?,
                  has_limited_access: auth.has_limited_access?,
                  has_paid_access: auth.has_paid_access?,
                  id: copilot_user.id,
                  is_model_picker_enabled: copilot_user.has_o1_models_access?,
                  limited_user_quotas: load_limited_user_quotas(copilot_user),
                  limited_user_reset_date: load_limited_user_reset_date(copilot_user),
                  mcp: load_copilot_mcp_setting(copilot_user),
                  mobile_chat_setting: load_copilot_mobile_chat_setting(copilot_user),
                  o1_setting: load_copilot_o1_setting(copilot_user),
                  o3_setting: load_copilot_o3_setting(copilot_user),
                  of_setting: load_copilot_of_setting(copilot_user),
                  off_setting: load_copilot_off_setting(copilot_user),
                  ofm_setting: load_copilot_ofm_setting(copilot_user),
                  ofo_setting: load_copilot_ofo_setting(copilot_user),
                  ot_setting: load_copilot_ot_setting(copilot_user),
                  pr_summarization: load_copilot_pr_summarization(copilot_user),
                  private_docs: load_copilot_private_docs(copilot_user),
                  skuisolation: load_copilot_sku_isolation(copilot_user),
                  snippy_setting: load_copilot_snippy_setting(copilot_user),
                  spammy: copilot_user.spammy?,
                  swe_agent_setting: load_copilot_swe_agent_setting(copilot_user),
                  telemetry_configuration: load_telemetry(copilot_user),
                  trust_tier: load_trust_tier(copilot_user)
                }
              }
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(T::Array[MonolithTwirp::Copilot::Users::V1::LimitedUserQuota]) }
        def load_limited_user_quotas(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_limited_user_quotas", kind: :internal) do
            limited_user = copilot_user.limited_user
            return [] unless limited_user

            monthly_quotas = Copilot::Quotas.monthly_quotas

            limited_user.quotas_remaining.map do |feature, remaining|
              quota = monthly_quotas[feature]
              MonolithTwirp::Copilot::Users::V1::LimitedUserQuota.new({
                feature: feature,
                remaining: [remaining, 0].max, # always be positive about yourself
                monthly_quota: quota,
              })
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(T.nilable(MonolithTwirp::Copilot::Users::V1::ResetDate)) }
        def load_limited_user_reset_date(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_limited_user_reset_date", kind: :internal) do
            limited_user = copilot_user.limited_user
            return nil unless limited_user

            reset_date = limited_user.reset_date
            return nil if reset_date.nil?

            MonolithTwirp::Copilot::Users::V1::ResetDate.new({
              year: reset_date.year,
              month: reset_date.month,
              day: reset_date.day,
            })
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_beta_features_opt_in_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_beta_features_opt_in_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_INVALID if copilot_user.has_limited_access?

            if copilot_user.beta_features_github_chat_enabled?
              MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_ENABLED
            elsif copilot_user.beta_features_github_chat_disabled?
              MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_DISABLED
            else
              MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_INVALID
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_bing_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_bing_setting", kind: :internal) do
            if copilot_user.bing_github_chat_enabled?
              MonolithTwirp::Copilot::Users::V1::Bing::BING_ENABLED
            elsif copilot_user.bing_github_chat_disabled?
              MonolithTwirp::Copilot::Users::V1::Bing::BING_DISABLED
            else
              MonolithTwirp::Copilot::Users::V1::Bing::BING_INVALID
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_custom_model(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_custom_model", kind: :internal) do
            # Custom Models is not part of the confirmed scope for Copilot Individuals Free/Limited Users
            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_INVALID if copilot_user.has_limited_access?

            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_UNCONFIGURED unless copilot_user.custom_models_configured?
            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_ENABLED if copilot_user.custom_models_enabled?
            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_DISABLED if copilot_user.custom_models_disabled?
            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_NO_POLICY if copilot_user.custom_models_no_policy?

            MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_desktop(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_desktop", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_UNCONFIGURED unless copilot_user.desktop_configured?
            return MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_ENABLED if copilot_user.desktop_enabled?
            return MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_DISABLED if copilot_user.desktop_disabled?

            MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_mcp_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_mcp_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::MCP::MCP_INVALID unless copilot_user.has_mcp_access?

            return MonolithTwirp::Copilot::Users::V1::MCP::MCP_ENABLED if copilot_user.mcp_enabled?
            return MonolithTwirp::Copilot::Users::V1::MCP::MCP_DISABLED if copilot_user.mcp_disabled?
            return MonolithTwirp::Copilot::Users::V1::MCP::MCP_UNCONFIGURED if !copilot_user.mcp_enabled? && !copilot_user.mcp_disabled?

            MonolithTwirp::Copilot::Users::V1::MCP::MCP_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_pr_summarization(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_pr_summarization", kind: :internal) do
            # PR Summaries is not part of the confirmed scope for Copilot Individuals Free/Limited Users
            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_INVALID if copilot_user.has_limited_access?

            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_UNCONFIGURED unless copilot_user.pr_summarizations_configured?
            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_ENABLED if copilot_user.pr_summarizations_enabled?
            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_DISABLED if copilot_user.pr_summarizations_disabled?
            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_NO_POLICY if copilot_user.pr_summarizations_no_policy?

            MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_g_chat_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_g_chat_setting", kind: :internal) do
            # GChat is not part of the confirmed scope for Copilot Individuals Free/Limited Users
            public_user = Copilot::Public::User.new(copilot_user.user_object)
            return MonolithTwirp::Copilot::Users::V1::GChat::G_CHAT_ENABLED if public_user.g_chat_enabled?
            return MonolithTwirp::Copilot::Users::V1::GChat::G_CHAT_DISABLED if public_user.g_chat_disabled?
            return MonolithTwirp::Copilot::Users::V1::GChat::G_CHAT_UNCONFIGURED if !public_user.g_chat_enabled? && !public_user.g_chat_disabled?

            MonolithTwirp::Copilot::Users::V1::GChat::G_CHAT_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_gtf_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_gtf_setting", kind: :internal) do
            # not part of the confirmed scope for Copilot Individuals Free/Limited Users
            return MonolithTwirp::Copilot::Users::V1::GTF::GTF_INVALID unless (copilot_user.has_cfb_access? || copilot_user.has_cfe_access?) || Copilot::Users::ModelAccess.model_available?(copilot_user, :g_tf)

            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::GTF::GTF_ENABLED if public_user.g_tf_enabled?
            return MonolithTwirp::Copilot::Users::V1::GTF::GTF_DISABLED if public_user.g_tf_disabled?
            return MonolithTwirp::Copilot::Users::V1::GTF::GTF_UNCONFIGURED if !public_user.g_tf_enabled? && !public_user.g_tf_disabled?

            MonolithTwirp::Copilot::Users::V1::GTF::GTF_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_gtff_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_gtff_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_INVALID unless copilot_user.user_object.feature_enabled?(:copilot_gtff)

            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_ENABLED if public_user.gtff_enabled?
            return MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_DISABLED if public_user.gtff_disabled?
            return MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_UNCONFIGURED if !public_user.gtff_enabled? && !public_user.gtff_disabled?

            MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_a_chat_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_a_chat_setting", kind: :internal) do
            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::AChat::A_CHAT_ENABLED if public_user.a_chat_enabled?
            return MonolithTwirp::Copilot::Users::V1::AChat::A_CHAT_DISABLED if public_user.a_chat_disabled?
            return MonolithTwirp::Copilot::Users::V1::AChat::A_CHAT_UNCONFIGURED if !public_user.a_chat_enabled? && !public_user.a_chat_disabled?

            MonolithTwirp::Copilot::Users::V1::AChat::A_CHAT_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_o1_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_o1_setting", kind: :internal) do
            # Copilot Individual Free users are blocked from using o1 now (after they were allowed yesterday - who know what tomorrow will bring)
            return MonolithTwirp::Copilot::Users::V1::O1::O1_INVALID if copilot_user.has_limited_access?

            public_user = Copilot::Public::User.new(copilot_user.user_object)
            return MonolithTwirp::Copilot::Users::V1::O1::O1_ENABLED if public_user.o1_enabled?
            return MonolithTwirp::Copilot::Users::V1::O1::O1_DISABLED if public_user.o1_disabled?
            return MonolithTwirp::Copilot::Users::V1::O1::O1_UNCONFIGURED if !public_user.o1_enabled? && !public_user.o1_disabled?

            MonolithTwirp::Copilot::Users::V1::O1::O1_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_o3_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_o3_setting", kind: :internal) do
            # Copilot Individual Free users are blocked from using o3
            public_user = Copilot::Public::User.new(copilot_user.user_object)
            return MonolithTwirp::Copilot::Users::V1::O3::O3_ENABLED if public_user.o3_enabled?
            return MonolithTwirp::Copilot::Users::V1::O3::O3_DISABLED if public_user.o3_disabled?
            return MonolithTwirp::Copilot::Users::V1::O3::O3_UNCONFIGURED if !public_user.o3_enabled? && !public_user.o3_disabled?

            MonolithTwirp::Copilot::Users::V1::O3::O3_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_af_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_af_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::AF::AF_INVALID if copilot_user.has_limited_access? && !copilot_user.user_object.feature_enabled?(:copilot_free_a_f)
            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::AF::AF_ENABLED if public_user.a_f_enabled?
            return MonolithTwirp::Copilot::Users::V1::AF::AF_DISABLED if public_user.a_f_disabled?
            return MonolithTwirp::Copilot::Users::V1::AF::AF_UNCONFIGURED if !public_user.a_f_enabled? && !public_user.a_f_disabled?

            MonolithTwirp::Copilot::Users::V1::AF::AF_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_afos_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_afos_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_INVALID unless copilot_user.user_object.feature_enabled?(:copilot_afos)
            return MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_INVALID unless (copilot_user.has_cfe_access? || copilot_user.has_cfb_access?) || Copilot::Users::ModelAccess.model_available?(copilot_user, :afos)
            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_ENABLED if public_user.afos_enabled?
            return MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_DISABLED if public_user.afos_disabled?
            return MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_UNCONFIGURED if !public_user.afos_enabled? && !public_user.afos_disabled?

            MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_al_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_al_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::AL::AL_INVALID unless copilot_user.user_object.feature_enabled?(:copilot_al)
            return MonolithTwirp::Copilot::Users::V1::AL::AL_INVALID unless copilot_user.has_cfe_access? || Copilot::Users::ModelAccess.model_available?(copilot_user, :al)
            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::AL::AL_ENABLED if public_user.al_enabled?
            return MonolithTwirp::Copilot::Users::V1::AL::AL_DISABLED if public_user.al_disabled?
            return MonolithTwirp::Copilot::Users::V1::AL::AL_UNCONFIGURED if !public_user.al_enabled? && !public_user.al_disabled?

            MonolithTwirp::Copilot::Users::V1::AL::AL_INVALID
          end
        end


        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_off_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_off_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::OFF::OFF_INVALID unless copilot_user.has_cfe_access? || Copilot::Users::ModelAccess.model_available?(copilot_user, :o_ff)
            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::OFF::OFF_ENABLED if public_user.o_ff_enabled?
            return MonolithTwirp::Copilot::Users::V1::OFF::OFF_DISABLED if public_user.o_ff_disabled?
            return MonolithTwirp::Copilot::Users::V1::OFF::OFF_UNCONFIGURED if !public_user.o_ff_enabled? && !public_user.o_ff_disabled?

            MonolithTwirp::Copilot::Users::V1::OFF::OFF_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_ofm_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_ofm_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::OFM::OFM_INVALID unless (copilot_user.has_cfb_access? || copilot_user.has_cfe_access?) || Copilot::Users::ModelAccess.model_available?(copilot_user, :o_fm)

            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::OFM::OFM_ENABLED if public_user.o_fm_enabled?
            return MonolithTwirp::Copilot::Users::V1::OFM::OFM_DISABLED if public_user.o_fm_disabled?
            return MonolithTwirp::Copilot::Users::V1::OFM::OFM_UNCONFIGURED if !public_user.o_fm_enabled? && !public_user.o_fm_disabled?

            MonolithTwirp::Copilot::Users::V1::OFM::OFM_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_ofo_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_ofo_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::OFO::OFO_INVALID unless (copilot_user.has_cfb_access? || copilot_user.has_cfe_access?) || Copilot::Users::ModelAccess.model_available?(copilot_user, :ofo)

            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::OFO::OFO_ENABLED if public_user.ofo_enabled?
            return MonolithTwirp::Copilot::Users::V1::OFO::OFO_DISABLED if public_user.ofo_disabled?
            return MonolithTwirp::Copilot::Users::V1::OFO::OFO_UNCONFIGURED if !public_user.ofo_enabled? && !public_user.ofo_disabled?

            MonolithTwirp::Copilot::Users::V1::OFO::OFO_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_swe_agent_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_swe_agent_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_INVALID unless copilot_user.has_swe_agent_access?

            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_ENABLED if public_user.swe_agent_enabled?
            return MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_DISABLED if public_user.swe_agent_disabled?
            return MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_UNCONFIGURED if !public_user.swe_agent_enabled? && !public_user.swe_agent_disabled?

            MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_of_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_of_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::OF::OF_INVALID if copilot_user.has_limited_access? && !copilot_user.user_object.feature_enabled?(:copilot_free_o_f)
            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::OF::OF_ENABLED if public_user.o_f_enabled?
            return MonolithTwirp::Copilot::Users::V1::OF::OF_DISABLED if public_user.o_f_disabled?
            return MonolithTwirp::Copilot::Users::V1::OF::OF_INVALID unless copilot_user.user_object.feature_enabled?(:copilot_o_f)
            return MonolithTwirp::Copilot::Users::V1::OF::OF_UNCONFIGURED if !public_user.o_f_enabled? && !public_user.o_f_disabled?

            MonolithTwirp::Copilot::Users::V1::OF::OF_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_ot_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_ot_setting", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::OT::OT_INVALID unless copilot_user.has_cfe_access? || Copilot::Users::ModelAccess.model_available?(copilot_user, :o_t)
            public_user = Copilot::Public::User.new(copilot_user.user_object)

            return MonolithTwirp::Copilot::Users::V1::OT::OT_ENABLED if public_user.o_t_enabled?
            return MonolithTwirp::Copilot::Users::V1::OT::OT_DISABLED if public_user.o_t_disabled?
            return MonolithTwirp::Copilot::Users::V1::OT::OT_INVALID unless copilot_user.user_object.feature_enabled?(:copilot_o_t)
            return MonolithTwirp::Copilot::Users::V1::OT::OT_UNCONFIGURED if !public_user.o_t_enabled? && !public_user.o_t_disabled?

            MonolithTwirp::Copilot::Users::V1::OT::OT_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_editor_preview_features_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_editor_preview_features_setting", kind: :internal) do
            # Copilot Individual Free users are blocked from using o3

            public_user = Copilot::Public::User.new(copilot_user.user_object)
            return MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_ENABLED if public_user.editor_preview_features_enabled?
            return MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_DISABLED if public_user.editor_preview_features_disabled?
            return MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_UNCONFIGURED if !public_user.editor_preview_features_enabled? && !public_user.editor_preview_features_disabled?

            MonolithTwirp::Copilot::Users::V1::EditorPreviewFeatures::EDITOR_PREVIEW_FEATURES_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_automatic_code_review_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_automatic_code_review_setting", kind: :internal) do
            public_user = Copilot::Public::User.new(copilot_user.user_object)
            return MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_ENABLED if public_user.automatic_code_review_enabled?
            return MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_DISABLED if public_user.automatic_code_review_disabled?
            return MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_UNCONFIGURED if !public_user.automatic_code_review_enabled? && !public_user.automatic_code_review_disabled?

            MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_private_docs(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_private_docs", kind: :internal) do
            # Private docs is not part of the confirmed scope for Copilot Individuals Free/Limited Users
            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_INVALID if copilot_user.has_limited_access?

            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_UNCONFIGURED unless copilot_user.private_docs_configured?
            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_ENABLED if copilot_user.private_docs_enabled?
            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_DISABLED if copilot_user.private_docs_disabled?
            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_NO_POLICY if copilot_user.private_docs_no_policy?

            MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(T.nilable(SKUIsolation)) }
        def load_copilot_sku_isolation(copilot_user)
          return if copilot_user.has_limited_access?

          sku_isolation = Copilot::SKUIsolation.new(copilot_user, GitHub::CurrentTenant.get)
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
              return MonolithTwirp::Copilot::Users::V1::CopilotPlan::COPILOT_PLAN_INDIVIDUAL_PRO if copilot_user.has_cfi_pro_plus_access?

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

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_editor_chat_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_editor_chat_setting", kind: :internal) do
            case copilot_user.copilot_editor_chat_setting
            when :EDITOR_CHAT_ENABLED
              # we treat Copilot Individuals Free/Limited Users differently. they have the same setting
              # available below but we need to check if they have chat quota remaining or not
              if copilot_user.has_chat_quota_remaining?
                # the first thing we check in ^^^ is if they are a limited user
                GitHub.dogstats.increment("copilot.twirp.editor_chat_quota_remaining")
                return MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_ENABLED
              else
                GitHub.dogstats.increment("copilot.twirp.editor_chat_quota_exceeded")
                # they don't have enough quota
                return MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_DISABLED
              end
            when :EDITOR_CHAT_DISABLED
              MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_DISABLED
            when :EDITOR_CHAT_UNCONFIGURED
              MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_UNCONFIGURED
            else
              MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_INVALID
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_mobile_chat_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_mobile_chat_setting", kind: :internal) do
            # Mobile is coming soon but not yet so if you have limited access and aren't in the FF, you don't get it
            if copilot_user.has_limited_access? && !copilot_user.user_object.feature_enabled?(:copilot_free_mobile)
              return MonolithTwirp::Copilot::Users::V1::MobileChat::MOBILE_CHAT_INVALID
            end

            # otherwise, we go with your mobile chat setting
            case copilot_user.copilot_mobile_chat_setting
            when :MOBILE_CHAT_ENABLED
              MonolithTwirp::Copilot::Users::V1::MobileChat::MOBILE_CHAT_ENABLED
            when :MOBILE_CHAT_DISABLED
              MonolithTwirp::Copilot::Users::V1::MobileChat::MOBILE_CHAT_DISABLED
            else
              MonolithTwirp::Copilot::Users::V1::MobileChat::MOBILE_CHAT_INVALID
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_snippy_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_snippy_setting", kind: :internal) do
            case copilot_user.copilot_snippy_setting
            when :SNIPPY_ENABLED
              MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_ENABLED
            when :SNIPPY_DISABLED
              MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_DISABLED
            when :SNIPPY_UNCONFIGURED
              MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_UNCONFIGURED
            else
              MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_INVALID
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_dotcom_chat_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_dotcom_chat_setting", kind: :internal) do
            # JUST KIDDING we treat Copilot Individuals Free/Limited Users EXACTLY THE SAME

            return MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_ENABLED if copilot_user.dotcom_chat_enabled?
            return MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_DISABLED if copilot_user.dotcom_chat_disabled?
            return MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_UNCONFIGURED unless copilot_user.dotcom_chat_configured?
            MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_cli_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.", kind: :internal) do
            # CLI will come to Copilot Free one day but not yet so if you have limited access and aren't in the FF, you don't get it
            # PV: I was already in here doing mobile so I thought I'd add CLI too.
            if copilot_user.has_limited_access? && !copilot_user.user_object.feature_enabled?(:copilot_free_cli)
              return MonolithTwirp::Copilot::Users::V1::CLI::CLI_INVALID
            end

            # otherwise, we go with your cli setting
            return MonolithTwirp::Copilot::Users::V1::CLI::CLI_ENABLED if copilot_user.cli_enabled?
            return MonolithTwirp::Copilot::Users::V1::CLI::CLI_DISABLED if copilot_user.cli_disabled?

            return MonolithTwirp::Copilot::Users::V1::CLI::CLI_UNCONFIGURED if copilot_user.cli_unconfigured?
            MonolithTwirp::Copilot::Users::V1::CLI::CLI_INVALID
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
      end
    end
  end
end
