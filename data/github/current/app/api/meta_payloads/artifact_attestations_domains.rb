# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::ArtifactAttestationsDomains
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.dnsdomains.fetch("artifact_attestations", {})
    else
      GitHub::Config::ArtifactAttestations.meta_info
    end
  end
end
