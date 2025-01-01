# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::Importer
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.github_source_importer_ips
    when "staff-wus2-01", "prod-weu-01", "prod-sdc-01", "prod-ae-01", "prod-cus-01", "test-cnc-01"
      [] # TODO: implement for other stamps
    else
      []
    end
  end
end
