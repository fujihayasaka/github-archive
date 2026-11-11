# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::Hooks
  def self.payload
    case GitHub::Config::Proxima.current_stamp_or_dotcom
    when "dotcom"
      GitHub.hook_ips
    when "staff-wus2-01"
      [
        "20.9.147.145/32",
        "20.115.217.0/32",
        "20.3.242.160/32",
      ]
    when "prod-weu-01"
      [
        "108.143.197.177/32",
        "20.123.213.97/32",
        "20.224.46.144/32",
      ]
    when "prod-sdc-01"
      [
        "20.240.220.192/32",
        "20.240.194.241/32",
        "20.240.211.209/32",
      ]
    when "prod-ae-01"
      [
        "20.5.226.112/32",
        "20.248.163.177/32",
        "4.237.73.192/32",
      ]
    when "prod-cus-01"
      [
        "48.214.149.97/32",
        "74.249.180.193/32",
        "172.202.123.177/32"
      ]
    else
      []
    end
  end
end
