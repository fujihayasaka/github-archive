# typed: true
# frozen_string_literal: true

class Api::Internal::CodeScanning < Api::Internal
  def externally_accessible?
    false
  end

  # Returns the integration IDs for the Code Scanning (Advanced Security) integration.
  get "/internal/code-scanning/integration", operation_id: :internal do
    integration = ::Apps::Privileged.integration(:code_scanning)
    deliver_error! 404, message: "The Code Scanning integration could not be found." if integration.nil?
    deliver_raw({
      id: integration.id,
      bot_grid: integration.bot.global_relay_id,
    })
  end
end
