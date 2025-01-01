# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateCopilotAgentSession < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Create a Copilot Agent session by accepting a user-entered problem statement and repository."

      read_arguments_from_replicas!

      read_mutation_fields_from_replicas!(ApplicationRecord::Repositories)

      required_capabilities [:copilot_agents]

      scopeless_tokens_as_minimum

      argument :repository_id, ID, "The node ID of the repository.", required: true, loads: Objects::Repository

      argument :problem_statement, String, "The user-entered problem statement.", required: true

      argument :base_ref, String, "The base ref to use for the Copilot Agent to base its work on.", required: true

      argument :creation_id, String, "An optional ID to track the session creation.", required: false

      argument :event_type, Platform::Enums::CopilotAgentEventType, "The type of event that triggered the creation of this session.", required: false, default_value: "unknown_graphql_event"

      field :session_id, String, "The unique identifier of the session.", null: true

      field :last_updated_at,
        Scalars::DateTime,
        "Identifies the date and time when the agent last made progress.",
        null: true

      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |current_org|
          permission.access_allowed?(
            :create_pull_request,
            repo: repository,
            current_org:,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:, problem_statement:, base_ref:, event_type:, **inputs)
        replica_clusters = [ApplicationRecord::Repositories]

        read_from_selected_replicas(replica_clusters) do
          # Gate this for internal testing (for now).
          unless @context[:viewer].feature_flag_enabled?(:graphql_copilot_agents, default: false)
            raise Errors::Forbidden.new("You do not have access to create Copilot Agent sessions.")
          end

          unless repository.copilot_swe_agent_enabled?(context[:viewer])
            raise Errors::Forbidden.new("Copilot Swe Agent app is not enabled in this repository.")
          end

          user = @context[:viewer]
          token = Copilot::DecryptedToken.from(@context[:request_token].to_s)
          event_type = resolve_event_type(event_type)

          response = user.copilot_api(integration_id: CopilotAPI::COPILOT_SWE_AGENT, token:)
            .create_swe_agent_job(
              nwo: repository.name_with_display_owner,
              problem_statement:,
              base_ref:,
              creation_id: inputs[:creation_id] || "",
              event_type:,
              api_version: "v1",
            )

          {
            session_id: response["session_id"],
            last_updated_at: response["updated_at"]
          }
        end
      end

      private

      def resolve_event_type(event_type)
        return event_type unless event_type.start_with?("mobile_")

        app = @context[:oauth_app] || @context[:integration]
        case app&.key
        when Apps::Privileged::Mobile::GITHUB_MOBILE_ANDROID_CLIENT_ID
          "android_#{event_type}"
        when Apps::Privileged::Mobile::GITHUB_MOBILE_IOS_CLIENT_ID
          "ios_#{event_type}"
        else
          "unknown_#{event_type}"
        end
      end
    end
  end
end
