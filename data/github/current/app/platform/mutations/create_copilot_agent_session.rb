# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateCopilotAgentSession < Platform::Mutations::Base
      docs_category :copilot
      include Platform::Helpers::ReadFromSelectedReplicas
      include Helpers::Agentic

      description "Create a Copilot Agent session by accepting a user-entered problem statement and repository."

      read_arguments_from_replicas!

      read_mutation_fields_from_replicas!(ApplicationRecord::Repositories)

      required_capabilities [:copilot_agents]

      scopeless_tokens_as_minimum

      argument :repository_id, ID, "The node ID of the repository.", required: true, loads: Objects::Repository

      argument :problem_statement, String, "The user-entered problem statement.", required: true

      argument :base_ref, String, "The base ref to use for the Copilot Agent to base its work on.", required: true

      argument :creation_id, String, "An optional ID to track the session creation.", required: false

      argument :model_id, String, "The ID of the model for the Copilot Agent to use.", required: false

      argument :event_type,
        Platform::Enums::CopilotAgentEventType,
        "The type of event that triggered the creation of this session.",
        required: false,
        default_value: "unknown_graphql_event"

      argument :custom_agent, String, "Custom agent identifier. (name of file)", required: false

      argument :agent_id, Integer, "The integration ID of the agent to use for the session.", required: false

      argument :event_content,
        String,
        "Optional additional content related to the event that triggered the creation of this session.",
        required: false

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

      def resolve(
        repository:,
        problem_statement:,
        base_ref:,
        event_type:,
        custom_agent: nil,
        agent_id: nil,
        event_content: nil,
        **inputs
      )
        replica_clusters = [ApplicationRecord::Repositories]

        read_from_selected_replicas(replica_clusters) do
          unless repository.copilot_swe_agent_enabled?(context[:viewer])
            raise Errors::Forbidden.new("Copilot Swe Agent app is not enabled in this repository.")
          end

          user = @context[:viewer]
          event_type = resolve_event_type(event_type)
          event_content = resolve_event_content(event_content, problem_statement)

          copilot_api = Copilot::User.copilot_api(user:, integration_id: CopilotAPI::COPILOT_SWE_AGENT, token: decrypted_capi_token)

          response = copilot_api.create_swe_agent_job(
              nwo: repository.name_with_display_owner,
              problem_statement:,
              base_ref:,
              creation_id: inputs[:creation_id] || "",
              event_type:,
              api_version: "v1",
              custom_agent: custom_agent,
              agent_id: agent_id,
              event_content:,
              model: inputs[:model_id] || "",
            )

          {
            session_id: response["session_id"],
            last_updated_at: response["updated_at"]
          }
        end
      end

      private

      def resolve_event_content(event_content, problem_statement)
        # If any non-null content is provided, use it as-is
        return event_content if event_content

        # However, if the user-supplied event_content is null and the origin is mobile
        # then default to the problem statement.
        # This should ease backfilling missing event content for mobile-originated sessions since
        # mobile updates require a new app version be downloaded and updated on client devices.
        case app&.key
        when Apps::Privileged::Mobile::GITHUB_MOBILE_ANDROID_CLIENT_ID,
          Apps::Privileged::Mobile::GITHUB_MOBILE_IOS_CLIENT_ID
          problem_statement
        else
          nil
        end
      end

      def app
        @context[:oauth_app] || @context[:integration]
      end

      def resolve_event_type(event_type)
        return event_type unless event_type.start_with?("mobile_")

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
