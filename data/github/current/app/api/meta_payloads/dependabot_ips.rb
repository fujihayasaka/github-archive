# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::DependabotIps
  # This class is used to return the Dependabot IPs for the GitHub API.
  # It is used in the /meta endpoint to provide information about the Dependabot IPs.
  def self.payload
    GitHub.dependabot_ips
  end
end
