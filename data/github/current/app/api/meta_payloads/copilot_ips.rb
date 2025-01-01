# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::CopilotIps
  # This class is used to return the Copilot IPs for the GitHub API.
  # It is used in the /meta endpoint to provide information about the Copilot IPs.
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.copilot_ips
    when "staff-wus2-01", "prod-weu-01", "prod-sdc-01", "prod-ae-01", "prod-cus-01", "test-cnc-01"
      GitHub.copilot_ips
    else
      []
    end
  end
end
