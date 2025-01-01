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

          model_publisher, model_name = req.model_key.split("/")
          return Twirp::Error.not_found("model was not found") unless model_publisher && model_name

          model = find_model(model_publisher, model_name)
          if model.nil? || !model.readable_by?(user)
            return Twirp::Error.not_found("model '#{model_name}' by publisher '#{model_publisher}' was not found")
          end

          flights = access_flights(actor)

          stats_prefix = "models.twirp.auth"

          if req.org_name.present?
            org = Organization.find_by(login: req.org_name)
            return Twirp::Error.not_found("organization was not found") unless org

            policy = GitHubModels::OrganizationAccessPolicy.new(org: org)

            has_access = validate_token_for_org_access(org, actor)
            return Twirp::Error.permission_denied("actor does not have access") unless has_access

            decision = policy.model_allowed?(model)
            customer_id = find_customer_id(org)
          else
            has_access = if actor.bot? && ::Apps::Privileged.capable?(:bypass_github_models_user_models_permission, app: actor.installation.integration)
              stats_prefix += ".actions"
              unless actor.installation.permissions["models"] == :read
                GitHub.dogstats.increment(stats_prefix + ".failure")
                return Twirp::Error.permission_denied("actor does not have the `models` permission")
              end
              true
            elsif user.feature_enabled?(:github_models_user_twirp_access)
              stats_prefix += ".user"
              check_user_token_scope(actor)
            else
              stats_prefix += ".user"
              true
            end
            GitHub.dogstats.increment(stats_prefix)
            return Twirp::Error.permission_denied("actor does not have access") unless has_access

            decision = model_allowed_by_flights?(flights, model)
            customer_id = find_customer_id(user)
          end

          {
            decision: decision,
            analytics_tracking_id: user.analytics_tracking_id,
            usage_tier: usage_tier(actor),
            flights: flights.join(","),
            is_staff: is_staff?(actor),
            customer_id: customer_id,
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

        sig { params(model_publisher: String, model_name: String).returns(T.nilable(GitHubModels::IModel)) }
        def find_model(model_publisher, model_name)
          # This could be an empty string if we get a parameter in the format of `/model-name`.
          # We don't want to unintentionally match the empty string, so we should return early.
          return unless model_publisher.present?

          model = GitHubModels.domain.models.find(original_name: model_name)
          return unless model

          if model.publisher_matches?(model_publisher)
            return model
          end

          nil
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
        sig { params(user: User).returns Integer }
        def usage_tier(user)
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
            return entity.customer&.id
          end

          if entity.delegate_billing_to_business?
            entity.business&.customer_id
          else
            entity.customer&.id
          end
        end
      end
    end
  end
end
