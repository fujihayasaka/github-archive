# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::CodespacesDomains
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.dnsdomains.fetch("codespaces", [])
    else
      []
    end
  end
end
