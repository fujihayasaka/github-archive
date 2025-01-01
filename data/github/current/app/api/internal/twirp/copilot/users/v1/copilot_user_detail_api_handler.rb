# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-users"

module Api::Internal::Twirp::Copilot
  module Users
    module V1
      # Handler for the MonolithTwirp::Copilot::Users::V1::CopilotUserDetailAPIService
      class CopilotUserDetailAPIHandler < Api::Internal::Twirp::Handler
        extend T::Sig

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
        ]
        handles_service MonolithTwirp::Copilot::Users::V1::CopilotUserDetailAPIService

        resolve_tenant_context only: [
          :get_copilot_user,
          :bulk_user_lookup
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

        private

        CopilotUserDetails = T.type_alias do
          {
            administrative_blocked: T.nilable(T::Boolean),
            analytics_tracking_id: T.nilable(String),
            bing_setting: T.nilable(T.any(Symbol, Integer)),
            cli_setting: T.nilable(T.any(Symbol, Integer)),
            copilot_access_type: T.nilable(T.any(Symbol, Integer)),
            copilot_organizations: T::Array[MonolithTwirp::Copilot::Users::V1::CopilotOrganization],
            copilot_plan: T.nilable(T.any(Symbol, Integer)),
            custom_model: T.nilable(T.any(Symbol, Integer)),
            dotcom_chat_setting: T.nilable(T.any(Symbol, Integer)),
            editor_chat_setting: T.nilable(T.any(Symbol, Integer)),
            has_cfb_access: T.nilable(T::Boolean),
            has_cfe_access: T.nilable(T::Boolean),
            has_cfi_access: T.nilable(T::Boolean),
            has_free_access: T.nilable(T::Boolean),
            has_paid_access: T.nilable(T::Boolean),
            id: T.nilable(Integer),
            latest_usage_detail_editor: T.nilable(String),
            latest_usage_detail: T.nilable(Google::Protobuf::Timestamp),
            mobile_chat_setting: T.nilable(T.any(Symbol, Integer)),
            pr_summarization: T.nilable(T.any(Symbol, Integer)),
            private_docs: T.nilable(T.any(Symbol, Integer)),
            skuisolation: T.nilable(SKUIsolation),
            snippy_setting: T.nilable(T.any(Symbol, Integer)),
            spammy: T.nilable(T::Boolean),
            telemetry_configuration: T.nilable(T.any(Symbol, Integer)),
            trust_tier: T.nilable(T.any(Symbol, Integer)),
            copilot_beta_features_opt_in_setting: T.nilable(T.any(Symbol, Integer)),
            content_exclusion_enabled: T.nilable(T::Boolean)
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
            copilot_organizations: T.nilable(T.any(Google::Protobuf::RepeatedField[MonolithTwirp::Copilot::Users::V1::CopilotOrganization], T::Array[MonolithTwirp::Copilot::Users::V1::CopilotOrganization])),
            id: T.nilable(Integer)
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
                ::User.where(analytics_tracking_id: batch_scope).each do |user|
                  bulk_user_details << {
                    id: user.id,
                    analytics_tracking_id: user.analytics_tracking_id,
                    copilot_organizations: Copilot::User.new(user).copilot_organizations.map do |copilot_organization|
                      MonolithTwirp::Copilot::Users::V1::CopilotOrganization.new({
                        id: copilot_organization.organization_object.id,
                        analytics_tracking_id: copilot_organization.organization_object.analytics_tracking_id,
                      })
                    end
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
              detail = copilot_user.latest_usage_detail
              access_type = load_access_type(auth)

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
                  administrative_blocked: copilot_user.administrative_blocked?,
                  analytics_tracking_id: copilot_user.user_object.analytics_tracking_id,
                  bing_setting: load_copilot_bing_setting(copilot_user),
                  cli_setting: load_copilot_cli_setting(copilot_user),
                  copilot_access_type: access_type,
                  copilot_organizations: load_organization_details(copilot_user),
                  copilot_plan: load_copilot_plan(copilot_user, access_type),
                  custom_model: load_copilot_custom_model(copilot_user),
                  dotcom_chat_setting: load_copilot_dotcom_chat_setting(copilot_user),
                  editor_chat_setting: load_copilot_editor_chat_setting(copilot_user),
                  has_cfb_access: auth.has_cfb_access?,
                  has_cfe_access: auth.has_cfe_access?,
                  has_cfi_access: auth.has_cfi_access?,
                  has_free_access: auth.access_type != :NO_ACCESS && !auth.has_paid_access?,
                  has_paid_access: auth.has_paid_access?,
                  id: copilot_user.id,
                  latest_usage_detail_editor: detail&.editor_details,
                  latest_usage_detail: Google::Protobuf::Timestamp.new(seconds: detail&.updated_at.to_i, nanos: 0),
                  mobile_chat_setting: load_copilot_mobile_chat_setting(copilot_user),
                  pr_summarization: load_copilot_pr_summarization(copilot_user),
                  private_docs: load_copilot_private_docs(copilot_user),
                  skuisolation: load_copilot_sku_isolation(copilot_user),
                  snippy_setting: load_copilot_snippy_setting(copilot_user),
                  spammy: copilot_user.spammy?,
                  telemetry_configuration: load_telemetry(copilot_user),
                  trust_tier: load_trust_tier(copilot_user),
                  copilot_beta_features_opt_in_setting: load_copilot_beta_features_opt_in_setting(copilot_user),
                  content_exclusion_enabled: copilot_user.copilot_content_exclusion_enabled?
                }
              }
            end
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_beta_features_opt_in_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_beta_features_opt_in_setting", kind: :internal) do
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
            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_UNCONFIGURED unless copilot_user.custom_models_configured?
            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_ENABLED if copilot_user.custom_models_enabled?
            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_DISABLED if copilot_user.custom_models_disabled?
            return MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_NO_POLICY if copilot_user.custom_models_no_policy?

            MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_pr_summarization(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_pr_summarization", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_UNCONFIGURED unless copilot_user.pr_summarizations_configured?
            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_ENABLED if copilot_user.pr_summarizations_enabled?
            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_DISABLED if copilot_user.pr_summarizations_disabled?
            return MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_NO_POLICY if copilot_user.pr_summarizations_no_policy?

            MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_private_docs(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_private_docs", kind: :internal) do
            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_UNCONFIGURED unless copilot_user.private_docs_configured?
            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_ENABLED if copilot_user.private_docs_enabled?
            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_DISABLED if copilot_user.private_docs_disabled?
            return MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_NO_POLICY if copilot_user.private_docs_no_policy?

            MonolithTwirp::Copilot::Users::V1::PrivateDocs::PRIVATE_DOCS_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(T.nilable(SKUIsolation)) }
        def load_copilot_sku_isolation(copilot_user)
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
            case auth.access_type
            when :NO_ACCESS, :ENTERPRISE_MANAGED
              MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_INVALID
            else
              if auth.access_type.to_s.include?("SEAT_ASSIGNMENT")
                GitHub.logger.info("Triggering seat assignment conversion", "gh.user.id" => auth.copilot_user.user_object.id)
                Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_later(
                  user_id: T.must(auth.copilot_user.user_object.id)
                )
              end

              "MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_#{auth.access_type}".constantize
            end
          end
        rescue NameError
          MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_INVALID
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_editor_chat_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_copilot_editor_chat_setting", kind: :internal) do
            case copilot_user.copilot_editor_chat_setting
            when :EDITOR_CHAT_ENABLED
              MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_ENABLED
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
            return MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_ENABLED if copilot_user.dotcom_chat_enabled?
            return MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_DISABLED if copilot_user.dotcom_chat_disabled?
            return MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_UNCONFIGURED unless copilot_user.dotcom_chat_configured?
            MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_INVALID
          end
        end

        sig { params(copilot_user: Copilot::User).returns(Integer) }
        def load_copilot_cli_setting(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.", kind: :internal) do
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

        sig { params(organization: ::Organization, user: ::User).returns(T::Boolean) }
        def org_allowed?(organization, user)
          GitHub.tracer.in_span("copilot.twirp.org_allowed", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.org_allowed") do
              # this is the cheapest check and hits most of the time
              return false unless organization.business.present?
              # this is the next cheapest - the business must have Copilot Enterprise
              return false unless Copilot::Organization.new(organization).can_use_copilot_enterprise_features?

              # these last two checks are roughly as bad, but we can do them either order and it times out the same
              return false unless organization.adminable_by?(user)
              !organization.has_sdn_new_org_with_free_plan_restriction?
            end
          end
        end
      end
    end
  end
end
