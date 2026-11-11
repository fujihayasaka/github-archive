# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-custom_instructions"

module Api::Internal::Twirp::Copilotapi
  module CustomInstructions
    module V1
      class CustomInstructionsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["copilot_api"]
        handles_service MonolithTwirp::Copilotapi::CustomInstructions::V1::CustomInstructionsAPIService

        sig do
          params(
            req: MonolithTwirp::Copilotapi::CustomInstructions::V1::CustomInstructionForUserIDRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::CustomInstructions::V1::CustomInstructionForUserIDResponse, Twirp::Error))
        end
        def custom_instruction_for_user_i_d(req, env)
          api_method = "custom_instruction_for_user_i_d"
          GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
            # check required arguments
            return access_token_not_provided(api_method) if req.access_token.blank?
            return user_id_not_provided(api_method) if req.user_id == 0 || req.user_id.blank?

            user = User.find_by(id: req.user_id)
            return user_not_found(api_method) unless user.present?

            custom_instruction = Copilot::CustomInstructions.for_user(user)
            return not_found(api_method) unless custom_instruction.present?

            allowed, viewer = validate_user_access(req.access_token, req.ip_address, custom_instruction)
            return user_not_found(api_method) unless viewer.present?
            return unauthorized(api_method) unless allowed

            MonolithTwirp::Copilotapi::CustomInstructions::V1::CustomInstructionForUserIDResponse.new(
              custom_instruction: to_custom_instruction_twirp(custom_instruction)
            )
          end
        end

        private

        def validate_user_access(access_token, ip_address, custom_instruction)
          viewer, = access_control(token: access_token, ip: ip_address)
          # Skip the access check for organization since we're only handling personal instruction at the moment.
          # For now you can only see your own personal instruction.
          allowed = custom_instruction.owner == viewer && Copilot::Public::User.new(viewer).has_copilot_access?

          [allowed, viewer]
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

        def not_found(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:not_found"])
          Twirp::Error.not_found("not found")
        end

        def user_id_not_provided(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:user_id"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
        end

        def access_token_not_provided(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:access_token"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "access_token")
        end

        def user_not_found(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:user_not_found"])
          Twirp::Error.not_found("user not found")
        end

        def unauthorized(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:not_authorized"])
          Twirp::Error.not_found("not found")
        end

        sig { params(custom_instruction: Copilot::CustomInstructions).returns(MonolithTwirp::Copilotapi::CustomInstructions::V1::CustomInstruction) }
        def to_custom_instruction_twirp(custom_instruction)
          MonolithTwirp::Copilotapi::CustomInstructions::V1::CustomInstruction.new(
            id: custom_instruction.id,
            owner_id: custom_instruction.owner_id,
            owner_type: custom_instruction.owner_type, # TODO: add Twirp owner type
            prompt: custom_instruction.prompt,
          )
        end
      end
    end
  end
end
