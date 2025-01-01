# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::DependabotIps
  # This class is used to return the Dependabot IPs for the GitHub API.
  # It is used in the /meta endpoint to provide information about the Dependabot IPs.
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.dependabot_ips
    when "staff-wus2-01", "prod-weu-01", "prod-sdc-01", "prod-ae-01", "prod-cus-01", "test-cnc-01"
      [] # TODO - implement this for the other stamps
    else
      []
    end
  end
end
