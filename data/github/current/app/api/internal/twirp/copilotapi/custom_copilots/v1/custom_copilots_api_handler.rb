# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-custom_copilots"

module Api::Internal::Twirp::Copilotapi
  module CustomCopilots
    module V1
      class CustomCopilotsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w[copilot_api copilot_spaces_github_mcp_server_remote]
        handles_service MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotsAPIService

        def cap_filter(request_ip)
          # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
          ConditionalAccess::Model::Filter.new(self, location: :model, actor: current_user, remote_ip: request_ip)
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigsForUserIDRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigsForUserIDResponse, Twirp::Error))
        end
        def custom_copilot_configs_for_user_i_d(req, env)
          @api_method = "custom_copilot_configs_for_user_id"
          started_at = Time.now
          GitHub.dogstats.distribution_time("copilot.twirp.#{@api_method}") do
            # check required arguments
            return access_token_not_provided if req.access_token.blank?
            return custom_copilot_user_id_not_provided unless req.present? && req.user_id != 0

            user = User.find_by(id: req.user_id)
            if !user.present?
              GitHub.logger.info("CopilotApi::CustomCopilots current user not found",
              "gh.copilotapi.custom_copilots.method": @api_method,
              "gh.copilotapi.custom_copilots.requested_user_id": req.user_id)
              return user_not_found
            end

            viewer, = access_control(token: req.access_token, ip: req.ip_address)
            # restrict to only the user themselves for now
            if viewer.nil? || viewer.id != user.id
              GitHub.logger.info("CopilotApi::CustomCopilots current user is not the requested user",
              "gh.copilotapi.custom_copilots.method": @api_method,
              "gh.copilotapi.custom_copilots.viewer_id": viewer&.id,
              "gh.copilotapi.custom_copilots.requested_user_id": req.user_id)
              return user_not_found
            end

            cap_filter = cap_filter(req.ip_address)

            filter_individual_spaces = !individual_access_enabled?(viewer)

            # We are excluding resources here to reduce payload size since this endpoint is used to list spaces
            # and the clients will fetch individual copilots to get the resources.
            configs = CopilotSpace.visible_to(viewer, cap_filter).filter_map do |copilot_space|
              next if filter_individual_spaces && copilot_space.owner.user?

              copilot_space.cap_filter = cap_filter
              copilot_space.current_user = viewer

              copilot_space.to_copilot_config_twirp(viewer)
            end

            return not_found unless configs.present?

            resp = MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigsForUserIDResponse.new(
              custom_copilot_configs: configs
            )

            CopilotSpaces::HydroEventsHelper.instrument_generic_event("custom_copilot_configs_for_user_id", viewer, nil, data: {
              controller: self.class.name,
              elapsed_time: Time.now - started_at,
            })

            resp
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForIDRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForIDResponse, Twirp::Error))
        end
        def custom_copilot_config_for_i_d(req, env)
          @api_method = "custom_copilot_config_for_id"
          started_at = Time.now
          GitHub.dogstats.distribution_time("copilot.twirp.#{@api_method}") do
            # check required arguments
            return access_token_not_provided if req.access_token.blank?
            return custom_copilot_id_not_provided if !id_provided?(req)

            copilot_space = if req.owner.present?
              owner = User.find_by_login(req.owner)
              return not_found unless owner.present?
              CopilotSpace.find_by(owner: owner, number: req.custom_copilot_id)
            else
              CopilotSpace.find_by(id: req.custom_copilot_id)
            end

            return not_found unless copilot_space.present?

            allowed, viewer = validate_user_copilot_space_access(req.access_token, req.ip_address, copilot_space)
            return user_not_found unless viewer.present?
            return unauthorized unless allowed

            copilot_space.cap_filter = cap_filter(req.ip_address)
            copilot_space.current_user = viewer

            limit_check_started_at = Time.now
            exceeds_limit = copilot_space.total_content_size_exceeds_limit?
            limit_check_elapsed_time_seconds = Time.now - limit_check_started_at

            if exceeds_limit
              CopilotSpaces::HydroEventsHelper.instrument_generic_event("custom_copilot_config_for_id", viewer, copilot_space, data: {
                controller: self.class.name,
                elapsed_time: Time.now - started_at,
                limit_check_elapsed_time_seconds: limit_check_elapsed_time_seconds,
                size_limit_exceeded: true
              })
              return size_limit_exceeded
            end

            build_response_started_at = Time.now
            resp = MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForIDResponse.new(
              custom_copilot_config: custom_copilot_config_response(copilot_space, req.access_token, req.ip_address, viewer)
            )

            build_response_elapsed_time_seconds = Time.now - build_response_started_at

            CopilotSpaces::HydroEventsHelper.instrument_generic_event("custom_copilot_config_for_id", viewer, copilot_space, data: {
              controller: self.class.name,
              elapsed_time: Time.now - started_at,
              limit_check_elapsed_time_seconds: limit_check_elapsed_time_seconds,
              build_response_elapsed_time_seconds: build_response_elapsed_time_seconds,
              size_limit_exceeded: false
            })

            resp
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForSlugRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForSlugResponse, Twirp::Error))
        end
        def custom_copilot_config_for_slug(req, env)
          @api_method = "custom_copilot_config_for_slug"
          GitHub.dogstats.distribution_time("copilot.twirp.#{@api_method}") do
            # check required arguments
            return access_token_not_provided if req.access_token.blank?
            return custom_copilot_slug_not_provided if req.slug.blank?
            return custom_copilot_owner_not_provided if req.owner.blank?

            owner = User.find_by_login(req.owner)
            return not_found unless owner.present?

            copilot_space = CopilotSpace.find_by(owner: owner, slug: req.slug)
            return not_found unless copilot_space.present?

            allowed, viewer = validate_user_copilot_space_access(req.access_token, req.ip_address, copilot_space)
            return user_not_found unless viewer.present?
            return unauthorized unless allowed

            MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForSlugResponse.new(
              custom_copilot_config: custom_copilot_config_response(copilot_space, req.access_token, req.ip_address, viewer)
            )
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForNameRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForNameResponse, Twirp::Error))
        end
        def custom_copilot_config_for_name(req, env)
          @api_method = "custom_copilot_config_for_name"
          started_at = Time.now
          GitHub.dogstats.distribution_time("copilot.twirp.#{@api_method}") do
            # check required arguments
            return access_token_not_provided if req.access_token.blank?
            return custom_copilot_owner_not_provided if req.owner.blank?
            return custom_copilot_name_not_provided if req.name.blank?

            owner = User.find_by_login(req.owner)
            return not_found unless owner.present?
            copilot_space = CopilotSpace.find_by(owner: owner, name: req.name)

            return not_found unless copilot_space.present?

            allowed, viewer = validate_user_copilot_space_access(req.access_token, req.ip_address, copilot_space)
            return user_not_found unless viewer.present?
            return unauthorized unless allowed

            copilot_space.cap_filter = cap_filter(req.ip_address)
            copilot_space.current_user = viewer

            limit_check_started_at = Time.now
            exceeds_limit = copilot_space.total_content_size_exceeds_limit?
            limit_check_elapsed_time_seconds = Time.now - limit_check_started_at

            if exceeds_limit
              CopilotSpaces::HydroEventsHelper.instrument_generic_event("custom_copilot_config_for_name", viewer, copilot_space, data: {
                controller: self.class.name,
                elapsed_time: Time.now - started_at,
                limit_check_elapsed_time_seconds: limit_check_elapsed_time_seconds,
                size_limit_exceeded: true
              })
              return size_limit_exceeded
            end

            build_response_started_at = Time.now
            resp = MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForNameResponse.new(
              custom_copilot_config: custom_copilot_config_response(copilot_space, req.access_token, req.ip_address, viewer)
            )

            build_response_elapsed_time_seconds = Time.now - build_response_started_at

            CopilotSpaces::HydroEventsHelper.instrument_generic_event("custom_copilot_config_for_name", viewer, copilot_space, data: {
              controller: self.class.name,
              elapsed_time: Time.now - started_at,
              limit_check_elapsed_time_seconds: limit_check_elapsed_time_seconds,
              build_response_elapsed_time_seconds: build_response_elapsed_time_seconds,
              size_limit_exceeded: false
            })

            resp
          end
        end

        sig do
          params(
            copilot_space: CopilotSpace,
            access_token: String,
            ip_address: String,
            viewer: User
          ).returns(MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfig)
        end
        def custom_copilot_config_response(copilot_space, access_token, ip_address, viewer)
          copilot_space.to_copilot_config_twirp(viewer) do |resource_repo|
            validate_repo_access(access_token, ip_address, resource_repo)
          end
        end

        def custom_copilot_id_not_provided
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:custom_copilot_id"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "custom_copilot_id")
        end

        def custom_copilot_owner_not_provided
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:owner"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "owner")
        end

        def custom_copilot_slug_not_provided
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:slug"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "slug")
        end

        def custom_copilot_name_not_provided
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:name"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "name")
        end

        def custom_copilot_user_id_not_provided
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:user_id"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
        end

        def access_token_not_provided
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:access_token"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "access_token")
        end

        def user_not_found
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:user_not_found"])
          Twirp::Error.not_found("user not found")
        end

        def org_not_found
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:org_not_found"])
          Twirp::Error.not_found("organization not found")
        end

        def unauthorized
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:not_authorized"])
          Twirp::Error.not_found("not found")
        end

        def not_found
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:not_found"])
          Twirp::Error.not_found("not found")
        end

        def size_limit_exceeded
          GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:size_limit_exceeded"])
          Twirp::Error.invalid_argument("size_limit_exceeded")
        end

        sig do
          params(
            access_token: String,
            ip_address: String,
            custom_copilot: CopilotSpace,
          ).returns([T::Boolean, T.nilable(User)])
        end
        def validate_user_copilot_space_access(access_token, ip_address, custom_copilot)
          viewer, _ = access_control(token: access_token, ip: ip_address)
          allowed = viewer ? custom_copilot.readable_by?(viewer) : false
          [allowed, viewer]
        end

        sig do
          params(
            access_token: String,
            ip_address: String,
            repo: Repository
          ).returns(T::Boolean)
        end
        def validate_repo_access(access_token, ip_address, repo)
          if repo.blank?
            GitHub.dogstats.increment("copilot.twirp.#{@api_method}.errors", tags: ["error:repo"])
            return false
          end

          _, ac = access_control(token: access_token, ip: ip_address)
          allowed = ac.access_allowed?(:get_contents,
            resource: repo,
            repo:,
            current_org: repo.owner&.organization? ? repo.owner : nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            raise_on_error: false
          )

          allowed
        end

        sig do
          params(
            token: String,
            ip: String
          ).returns([T.nilable(User), CopilotAPI::AccessControl])
        end
        def access_control(token:, ip:)
          auth_options = {
            token:,
            ip:
          }

          current_user = T.let(nil, T.nilable(User))
          if GitHub::Authentication::SignedAuthToken.valid_format?(token)
            parsed_token = GitHub::Authentication::SignedAuthToken.verify(
              token:,
              scope: Copilot::User::CopilotApi::SSAT_SCOPE_GITHUB_CHAT,
            )

            current_user = parsed_token.user
            auth_options[:authenticated_actor_using_web_session] = true
            auth_options[:viewer] = parsed_token.user
            auth_options[:user_session] = parsed_token.session
          end

          ac = CopilotAPI::AccessControl.new(auth_options)

          viewer = current_user || ac.user

          [viewer, ac]
        end

        private

        sig { params(req: MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfigForIDRequest).returns(T.nilable(T::Boolean)) }
        def id_provided?(req)
          req.custom_copilot_id.present? && req.custom_copilot_id != 0
        end

        sig { params(user: User).returns(T::Boolean) }
        def individual_access_enabled?(user)
          return true unless FeatureFlag.vexi.enabled?(:copilot_spaces_block_individual_access, user, default: false)

          Copilot::Policies::SpacesIndividualAccess.effective_value(Copilot::User.new(user)) == "enabled"
        end
      end
    end
  end
end
