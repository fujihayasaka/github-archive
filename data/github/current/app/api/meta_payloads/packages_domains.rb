# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::PackagesDomains
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.dnsdomains.fetch("packages", [])
    else
      []
    end
  end
end
