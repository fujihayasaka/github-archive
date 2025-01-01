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

          # If this is the GitHub App, we need to check if the app has the `models` permission
          if actor.bot? && actor.installation.launch_github_app?
            unless actor.installation.permissions["models"] == :read
              return Twirp::Error.unauthenticated("actor does not have the `models` permission")
            end
          end

          has_playground_access = GitHubModels::PlaygroundAccessResult.for(actor).accessible?
          return Twirp::Error.not_found("actor does not have access to playground") unless has_playground_access

          model_publisher, model_name = req.model_key.split("/")
          return Twirp::Error.not_found("model was not found") unless model_publisher && model_name

          catalog_item = find_catalog_item(model_publisher, model_name)
          return Twirp::Error.not_found("model was not found") unless catalog_item

          flights = access_flights(actor)

          decision = if req.org_name.present?
            org = Organization.find_by(login: req.org_name)
            return Twirp::Error.not_found("organization was not found") unless org

            policy = GitHubModels::OrganizationAccessPolicy.new(org: org)

            has_access = validate_token_for_org_access(org, actor)
            return Twirp::Error.not_found("actor does not have access") unless has_access

            policy.model_allowed?(catalog_item)
          else
            model_allowed_by_flights?(flights, catalog_item)
          end

          user_for_rate_limiting = actor.bot? ? actor.installation.target : actor

          {
            decision: decision,
            analytics_tracking_id: user_for_rate_limiting.analytics_tracking_id,
            usage_tier: usage_tier(actor),
            flights: flights.join(","),
            is_staff: is_staff?(actor)
          }
        end

        private

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

        sig { params(model_publisher: String, model_name: String).returns(T.nilable(GitHubModels::CatalogItem)) }
        def find_catalog_item(model_publisher, model_name)
          # This is OK because the catalog item table has 20 rows and will at most grow to one or two thousand
          # rubocop:disable GitHub/DoNotUseLower
          item = GitHubModels::CatalogItem.find_by("LOWER(original_name) = LOWER(?)", model_name)
          return unless item

          if item.publisher&.downcase == model_publisher.downcase
            return item
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

        sig { params(flights: T::Array[String], catalog_item: GitHubModels::CatalogItem).returns(T::Boolean) }
        def model_allowed_by_flights?(flights, catalog_item)
          restricted_models = FLIGHTS.values.flatten
          return true unless restricted_models.include?(catalog_item.name)

          FLIGHTS.keys.each do |flight|
            if flights.include?(flight) && FLIGHTS[flight].include?(catalog_item.name)
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
      end
    end
  end
end
