# typed: true
# frozen_string_literal: true

module Octoshift
  class ValidationHelper
    def self.allows_octoshift_ips?(owner)
      # default to true
      allows_ip = true

      # check if requested ip is valid if the owner has any GitHub.hook_ips IP allowlist enabled
      if owner.ip_allowlist_enabled? || owner.ip_allowlist_enabled_policy?
        ip_allowlist_entries = IpAllowlistEntry.usable_for(owner).active.pluck(:allow_list_value)
        ip_allowlist_entries.map!(&:downcase)

        allows_ip = (GitHub.github_enterprise_importer_ips - ip_allowlist_entries).empty?
      end

      allows_ip
    end
  end
end
