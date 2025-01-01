# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::Packages
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.packages_ips
    when "staff-wus2-01", "prod-weu-01", "prod-sdc-01", "prod-ae-01", "prod-cus-01", "test-cnc-01"
      [] # TODO: implement for other stamps
    else
      []
    end
  end
end
