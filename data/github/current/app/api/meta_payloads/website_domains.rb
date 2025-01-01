# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::WebsiteDomains
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.dnsdomains.fetch("website", [])
    else
      []
    end
  end
end
