# typed: strict
# frozen_string_literal: true

module Copilot
  class SweAgentJob < CopilotJob
    queue_as :copilot

    retry_on_dirty_exit

    resolve_tenant_context do |user_id:, **|
      user = ::User.find_by(id: user_id)
      user&.business
    end

    sig do
      params(
        user_id: Integer,
        nwo: String,
        problem_statement: String,
        base_ref: String,
        creation_id: String,
        event_type: String,
        user_session: T.nilable(::UserSession),
      ).void
    end
    def perform(
      user_id:,
      nwo:,
      problem_statement:,
      base_ref:,
      creation_id:,
      event_type:,
      user_session:
    )
      user = ::User.find_by(id: user_id)
      return unless user

      token = CopilotSweAgent::CopilotApiToken.get_encrypted(
        user: user,
        entry_point: :repositories_controller_create,
        user_session:,
      )

      copilot_api = user.copilot_api(integration_id: CopilotAPI::COPILOT_SWE_AGENT, token:)

      result = copilot_api.create_swe_agent_job(
        nwo: nwo,
        problem_statement: problem_statement,
        base_ref: base_ref,
        creation_id: creation_id,
        event_type: event_type
      )

      GitHub.logger.info(
        "SWE Agent job created successfully",
        nwo: nwo,
        creation_id: creation_id,
        event_type: event_type,
        result: result
      )
    rescue => error
      handle_copilot_error(
        Copilot::Errors::CopilotError.new("Failed to create SWE Agent job: #{error.message}"),
        {
          user_id: user_id,
          nwo: nwo,
          problem_statement: problem_statement,
          creation_id: creation_id,
          event_type: event_type,
          error_class: error.class.name,
          error_message: error.message
        }
      )
      raise
    end
  end
end
