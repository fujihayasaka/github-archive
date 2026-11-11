# typed: true
# frozen_string_literal: true

class Api::Internal::CodeCoverageAgent < Api::Internal
  def externally_accessible?
    false
  end

  # Returns the integration ID for the Code Coverage Agent integration.
  get "/internal/code-coverage-agent/integration", operation_id: :internal do
    integration = ::Apps::Privileged.integration(:code_coverage_agent)
    deliver_error! 404, message: "The Code Coverage Agent integration could not be found." if integration.nil?

    deliver_raw({ id: integration.id })
  end
end
