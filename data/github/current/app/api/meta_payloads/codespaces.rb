# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::Codespaces
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.codespaces_vm_ip_ranges
    when "staff-wus2-01", "prod-cus-01"
      # EastUs, EastUs2, WestUs2, WestUs3
      GitHub.codespaces_vm_ip_ranges_east_us +
        GitHub.codespaces_vm_ip_ranges_east_us_2 +
        GitHub.codespaces_vm_ip_ranges_west_us_2 +
        GitHub.codespaces_vm_ip_ranges_west_us_3
    when "prod-weu-01", "prod-sdc-01"
      # WestEurope
      GitHub.codespaces_vm_ip_ranges_west_europe
    when "prod-ae-01"
      # AustraliaCentral, AustraliaEast
      GitHub.codespaces_vm_ip_ranges_australia_central +
        GitHub.codespaces_vm_ip_ranges_australia_east
    when "prod-jpw-01"
      # JapanWest
      GitHub.codespaces_vm_ip_ranges_japan_west
    when "test-cnc-01"
      []
    else
      []
    end
  end
end
