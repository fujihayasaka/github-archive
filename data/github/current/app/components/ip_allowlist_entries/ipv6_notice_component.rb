# typed: true
# frozen_string_literal: true

class IpAllowlistEntries::Ipv6NoticeComponent < ApplicationComponent
  NOTICE_NAME = "ip_allowlist_ipv6"

  attr_reader :owner, :dismissal_path, :dismissal_method

  def initialize(owner:, dismissal_path:, dismissal_method:)
    @owner = owner
    @dismissal_path = dismissal_path
    @dismissal_method = dismissal_method
  end

  def render?
    show_notice?
  end

  private

  def show_notice?
    return false if GitHub.enterprise?
    return false if dismissed_notice?

    ip_allowlist_set_up?
  end

  def dismissed_notice?
    if owner.is_a?(Business)
      current_user.dismissed_business_notice?(NOTICE_NAME, business_id: owner.id)
    elsif owner.is_a?(Organization)
      current_user.dismissed_organization_notice?(NOTICE_NAME, owner)
    elsif owner.is_a?(Integration)
      current_user.dismissed_notice?(NOTICE_NAME)
    end
  end

  def ip_allowlist_set_up?
    if owner.is_a?(Business) || owner.is_a?(Organization)
      owner.ip_allowlist_enabled?
    elsif owner.is_a?(Integration)
      IpAllowlistEntry.usable_for(owner).any?
    end
  end

  def owner_type
    if owner.is_a?(Business)
      "enterprise"
    elsif owner.is_a?(Organization)
      "organization"
    elsif owner.is_a?(Integration)
      "GitHub App"
    end
  end

  def learn_more_url
    path = if owner.is_a?(Business)
      "/admin/configuration/hardening-security-for-your-enterprise/restricting-network-traffic-to-your-enterprise-with-an-ip-allow-list"
    elsif owner.is_a?(Organization)
      "/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization"
    elsif owner.is_a?(Integration)
      "/apps/maintaining-github-apps/managing-allowed-ip-addresses-for-a-github-app"
    end

    "#{GitHub.help_url}/#{path}"
  end
end
