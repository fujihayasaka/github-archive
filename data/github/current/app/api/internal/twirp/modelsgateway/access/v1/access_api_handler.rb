# typed: true
# frozen_string_literal: true

require "monolith-twirp-modelsgateway-access"

module Api::Internal::Twirp::Modelsgateway
  module Access
    module V1
      # Handler for the MonolithTwirp::Modelsgateway::Access::V1::AccessAPIService
      class AccessAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["modelsgateway"]
        handles_service MonolithTwirp::Modelsgateway::Access::V1::AccessAPIService

        REQUIRED_GET_MODEL_ACCESS_PARAMS = %w[access_token model_key].freeze
        FLIGHTS = {
          "o1-models" => %w[o1-preview o1-mini o1],
          "o3-models" => %w[o3-preview o3-mini o3]
        }

        # Public: Implementation of the GetModelAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Modelsgateway::Access::V1::GetModelAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Modelsgateway::Access::V1::GetModelAccessResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Modelsgateway::Access::V1::GetModelAccessRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_model_access(req, env)
          if error = request_validation_error(req)
            return error
          end

          api_auth = GitHub::Authentication::Attempt.new(
            allow_user_via_granular_actor: true,
            allow_integrations: true,
            from: :models_gateway,
            token: req.access_token,
            password_auth_blocked: true,
          )
          result = api_auth.result
          return Twirp::Error.unauthenticated("token is not valid") unless result.success?

          actor = result.user
          user = actor.bot? ? actor.installation.target : actor

          # Update usage details for the user
          ActiveRecord::Base.connected_to(role: :writing) do
            ::GitHubModels.domain.usage.create_or_update(user_id: user.id)
          end

          has_playground_access = GitHubModels::PlaygroundAccessResult.for(user).accessible?
          return Twirp::Error.permission_denied("actor does not have access to playground") unless has_playground_access

          # Is this an org request?
          # Org requests come in two ways:
          # 1. org_name is present, happens when user used the /org endpoints in gateway
          # 2. org_name is not present but request comes from GitHub Actions, in this case we use the org of the actor
          org_login = req.org_name
          if actor_is_github_actions?(actor) && org_login.blank?
            if actor.installation.present? && actor.installation.target.is_a?(Organization)
              org_login = actor.installation.target.login
            end
          end

          if org_login.present?
            org = Organization.find_by(login: org_login)
            return Twirp::Error.not_found("organization was not found") unless org
          end

          # Require provider and model name
          model_provider, model_publisher, model_name = parse_model_key(req.model_key)
          unless model_provider.present? && model_name.present?
            return Twirp::Error.not_found("model was not found")
          end

          # Find model
          model = case model_provider
          when ModelsByok::CustomModel::REGISTRY
            if org.present?
              find_custom_model(org, model_publisher, model_name)
            end
          else
            find_default_model(model_publisher, model_name)
          end

          if model.nil? || !model.readable_by?(user)
            return Twirp::Error.not_found("model '#{model_name}' by publisher '#{model_publisher}' was not found")
          end
          is_billable_model = GitHubModels::Multiplier.find_by(models_slug: model.slug).present?

          flights = access_flights(user)

          stats_prefix = "models.twirp.auth"

          is_billing_enabled = false
          organization_id = nil

          if org.present?
            has_access = validate_token_for_org_access(org, actor)
            return Twirp::Error.permission_denied("actor does not have access") unless has_access

            policy = GitHubModels::OrganizationAccessPolicy.new(org: org)
            decision = policy.model_allowed?(model)
            customer_id = find_customer_id(org)
            organization_id = org.id
            is_billing_enabled = is_billing_enabled_for_org?(org)
          else
            has_access = if actor.bot? && ::Apps::Privileged.capable?(:bypass_github_models_user_models_permission, app: actor.installation.integration)
              stats_prefix += ".actions"
              unless actor.installation.permissions["models"] == :read
                GitHub.dogstats.increment(stats_prefix + ".failure")
                return Twirp::Error.permission_denied("actor does not have the `models` permission")
              end
              true
            else
              stats_prefix += ".user"
              check_user_token_scope(actor)
            end

            GitHub.dogstats.increment(stats_prefix)
            return Twirp::Error.permission_denied("actor does not have access") unless has_access

            decision = model_allowed_by_flights?(flights, T.cast(model, GitHubModels::IModel))
            customer_id = find_customer_id(user)

            is_billing_enabled = is_models_billing_enabled?(user)
          end

          # Return custom model, if requested
          if model.is_a?(ModelsByok::CustomModel)
            custom_key = T.must(model.custom_key)

            custom_model = {
              owner_id: T.must(model.organization).next_global_id,
              provider: custom_key.provider,
              model_id: model.slug,
              key_secret_name: custom_key.kredz_key,
            }

            if custom_key.azureai?
              custom_model[:azure_ai] = {
                deployment_url: custom_key.deployment_url
              }
            end
          end

          is_paid_request = is_billing_enabled &&
            is_billable_model &&
            customer_id.present? &&
            req.is_billable_source

          {
            decision: decision,
            analytics_tracking_id: user.analytics_tracking_id,
            usage_tier: usage_tier(actor, is_paid_request),
            flights: flights.join(","),
            is_staff: is_staff?(actor),
            customer_id: customer_id,
            organization_id: organization_id,
            is_billing_enabled: is_paid_request, # This field must be true if the usage tier is paid
            custom_model: custom_model
          }
        end

        private

        sig { params(actor: T.any(User, Bot)).returns T::Boolean }
        def check_user_token_scope(actor)
          Api::AccessControl.access_allowed?(
            user: actor,
            verb: :read_user_models,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end

        sig do
          params(
            org: Organization,
            actor: T.any(User, Bot),
          ).returns(T::Boolean)
        end
        def validate_token_for_org_access(org, actor)
          Api::AccessControl.access_allowed?(
            resource: org,
            user: actor,
            verb: :read_org_models,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end

        def parse_model_key(model_key)
          parts = model_key.split("/")

          case parts.length
          when 2
            # Format: "model_publisher/model_name"
            provider = "azureml"  # default provider
            publisher = parts[0]
            name = parts[1]
          when 3
            # Format: "model_provider/model_publisher/model_name"
            provider = parts[0]
            publisher = parts[1]
            name = parts[2]
          end

          [provider, publisher, name]
        end

        sig { params(model_publisher: String, model_name: String).returns(T.nilable(GitHubModels::IModel)) }
        def find_default_model(model_publisher, model_name)
          model = GitHubModels.domain.models.find(original_name: model_name)
          return unless model

          if !model_publisher.present? || model.publisher_matches?(model_publisher)
            return model
          end

          nil
        end


        sig { params(org: Organization, model_key_name: T.nilable(String), model_name: T.nilable(String)).returns(T.nilable(ModelsByok::CustomModel)) }
        def find_custom_model(org, model_key_name, model_name)
          return unless model_key_name.present? && model_name.present?

          ModelsByok::CustomModel.for_org(org).find_by(slug: model_name, custom_keys: { name: model_key_name })
        end

        sig { params(user: T.nilable(User)).returns T::Boolean }
        def is_staff?(user)
          return false unless user
          return false unless user.user?

          ::GitHubModels::User.new(user: user).is_staff?
        end

        # We're interested in the feature flags on the acting user so we can handle
        # the Actions server-to-server use case.
        sig { params(user: T.nilable(User)).returns T::Array[String] }
        def access_flights(user)
          ::GitHubModels::User.new(user: user).access_flights
        end

        # Note that we need to +1 to the usage tier defined in GitHubModels::User, because the 0 value in protobuf enums
        # is reserved for the "unknown" value. This is one higher than in the old github_models internal API.
        sig { params(user: User, is_paid_request: T.nilable(T::Boolean)).returns Integer }
        def usage_tier(user, is_paid_request)
          if is_paid_request
            return ::GitHubModels::User::USAGE_TIERS[:PAY_GH] + 1
          end

          ::GitHubModels::User.new(user: user).usage_tier + 1
        end

        sig { params(flights: T::Array[String], model: GitHubModels::IModel).returns(T::Boolean) }
        def model_allowed_by_flights?(flights, model)
          restricted_models = FLIGHTS.values.flatten
          return true unless restricted_models.include?(model.name)

          FLIGHTS.keys.each do |flight|
            if flights.include?(flight) && FLIGHTS[flight].include?(model.name)
              return true
            end
          end

          false
        end

        sig do
          params(
            req: MonolithTwirp::Modelsgateway::Access::V1::GetModelAccessRequest
          ).returns(T.nilable(Twirp::Error))
        end
        def request_validation_error(req)
          missing_param = REQUIRED_GET_MODEL_ACCESS_PARAMS.detect { |param| req[param].blank? }

          return unless missing_param

          Twirp::Error.invalid_argument("must be non-empty", argument: missing_param)
        end

        sig { params(entity: T.nilable(T.any(User, Organization, Business))).returns(T.nilable(Integer)) }
        def find_customer_id(entity)
          return nil unless entity

          if entity.is_a?(Business)
            customer = entity.ensure_customer
            return customer&.id
          end

          customer = entity.ensure_customer_and_budget
          customer&.id
        end

        sig { params(entity: T.nilable(T.any(User, Organization, Business))).returns(T::Boolean) }
        def is_models_billing_enabled?(entity)
          entity&.models_billing_enabled? || false
        end


        sig { params(org: Organization).returns(T::Boolean) }
        def is_billing_enabled_for_org?(org)
          # NOTE: the direct org check here isn't gated by the feature flag, but `is_models_billing_enabled?` will
          # return false if the feature flag is not enabled. This && allows the org to disable billing if the
          # the business has it enabled.
          is_models_billing_enabled?(org)
        end

        sig { params(actor: T.any(User, Bot)).returns T::Boolean }
        def actor_is_github_actions?(actor)
          return false unless actor.bot? && actor.respond_to?(:installation)
          T.unsafe(actor).installation.launch_github_app?
        end
      end
    end
  end
end
