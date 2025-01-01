# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::CopilotDomains
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.dnsdomains.fetch("copilot", [])
    else
      []
    end
  end
end
