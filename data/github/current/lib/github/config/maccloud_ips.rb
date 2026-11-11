# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module MacCloudIPs
      # IP addresses of GitHub Mac hosted runners for Actions. This list is included
      # into the larger list of all GitHub hosted runners but many MacOS customers find
      # large list unberable to manage and so we also expose Mac IP addresses separately
      # for their convenience
      MACCLOUD_IP_CIDR = %w(
        13.105.117.0/24
        13.105.220.0/25
        13.105.220.128/27
        13.105.220.160/28
        13.105.220.176/29
        13.105.220.184/30
        13.105.220.188/31
        13.105.49.0/24
      )

      def maccloud_ips
        return @maccloud_ips if defined?(@maccloud_ips)
        if !GitHub.enterprise?
          @maccloud_ips = MACCLOUD_IP_CIDR
        else
          []
        end
      end
      attr_writer :maccloud_ips
    end
  end

  extend Config::MacCloudIPs
end
