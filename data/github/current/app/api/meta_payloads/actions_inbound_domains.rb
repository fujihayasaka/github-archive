# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::ActionsInboundDomains
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.dnsdomains.fetch("actions_inbound", {})
    else
      {}
    end
  end
end
