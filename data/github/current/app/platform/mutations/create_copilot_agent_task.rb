# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateCopilotAgentTask < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas
      include Helpers::Agentic

      description "Create a Copilot Agent Task by accepting a user-entered problem statement and repository."

      read_arguments_from_replicas!

      read_mutation_fields_from_replicas!(ApplicationRecord::Repositories)

      required_capabilities [:copilot_agents]

      scopeless_tokens_as_minimum

      argument :repository_id,
        ID,
        "The node ID of the repository.",
        required: true,
        loads: Objects::Repository

      argument :problem_statement,
        String,
        "User-entered prompt plus whatever metadata required for the Agent to perform its task.",
        required: false

      argument :base_ref,
        String,
        "The base ref to use for the Copilot Agent to base its work on.",
        required: false

      argument :model,
        String,
        "The ID of the model for the Copilot Agent to use.",
        required: false

      argument :event_type,
        Platform::Enums::CopilotAgentEventType,
        "The type of event that triggered the creation of this task.",
        required: false,
        default_value: "unknown_graphql_event"

      argument :custom_agent,
        String,
        "Custom agent identifier. (name of file)",
        required: false

      argument :event_content,
        String,
        "User-entered prompt.",
        required: false

      argument :create_pull_request,
        Boolean,
        "Whether the task should generate a pull request upon completion.",
        required: false

      argument :agent_id,
        Integer, "The integration ID of the agent to use.",
        required: false

      field :task, Objects::CopilotAgentTask, "The created Copilot Agent Task.", null: true

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
        agent_id: nil,
        base_ref: nil,
        create_pull_request: nil,
        custom_agent: nil,
        event_content: nil,
        event_type: nil,
        model: nil,
        problem_statement: nil,
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

          task = CopilotSessions::TaskApi::Task.create(
            repository:,
            user:,
            token: decrypted_capi_token,
            agent_id:,
            base_ref:,
            create_pull_request:,
            custom_agent:,
            entry_point: :create_agent_task_via_graphql,
            event_content:,
            event_type:,
            model:,
            problem_statement:,
          )

          { task: }
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
