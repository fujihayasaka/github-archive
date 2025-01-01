# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::GitHubEnterpriseImporter
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.github_enterprise_importer_ips
    when "staff-wus2-01"
      [
        "4.205.153.224/28",
        "4.229.40.128/28",
        "52.190.176.176/28",
        "4.246.86.240/28",
      ]
    when "prod-weu-01"
      [
        "4.231.155.80/29",
        "4.225.9.96/29",
        "51.12.152.184/29",
        "20.199.6.80/29",
      ]
    when "prod-sdc-01"
      [
        "51.12.144.32/29",
        "20.199.1.232/29",
        "51.12.152.240/29",
        "20.19.101.136/29",
      ]
    when "prod-ae-01"
      [
        "20.213.236.72/29",
        "20.53.178.216/29",
        "20.213.241.72/29",
        "20.11.90.48/29",
      ]
    when "prod-cus-01"
      [
        "130.213.245.128/28",
        "20.171.204.144/28",
        "20.171.204.176/28",
        "4.150.167.192/28",
      ]
    when "test-cnc-01"
      []
    else
      []
    end
  end
end
