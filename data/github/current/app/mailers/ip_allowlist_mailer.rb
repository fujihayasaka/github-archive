# typed: true
# frozen_string_literal: true

class IpAllowlistMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/ip_allowlist"

  helper :application
  helper :avatar

  layout "layouts/primer_layout"

  # Public: Notify an owner of an IP allow list that they need to add
  # any necessary IPv6 addresses to their allow list.
  #
  # owner - Business, Organization, or Integration that owns the IP allow list.
  #
  # Returns Mail.
  def ipv6_notice(owner)
    return unless should_send_ipv6_notice?(owner)

    @owner = owner
    @owner_name_and_type = owner_name_and_type(owner)
    @ip_allowlist_url = ip_allowlist_url(owner)

    premail(
      from: github,
      bcc: ip_allowlist_owner_emails(@owner),
      subject: "[GitHub] Update the #{@owner_name_and_type}'s IP allow list for IPv6",
    )
  end

  private

  def should_send_ipv6_notice?(owner)
    case owner
    when Business, Organization
      return true if owner.ip_allowlist_enabled?
    when Integration
      return true if owner.ip_allowlist_entries.any?
    end

    false
  end

  def owner_name_and_type(owner)
    case owner
    when Business
      "#{owner.name} enterprise"
    when Organization
      "#{owner.safe_profile_name} organization"
    when Integration
      "#{owner.name} GitHub App"
    end
  end

  def ip_allowlist_url(owner)
    case owner
    when Business
      settings_security_enterprise_url(owner.slug)
    when Organization
      settings_org_security_url(owner.display_login)
    when Integration
      if owner.owner.organization?
        settings_org_app_url(owner.owner.display_login, owner.slug)
      else
        settings_user_app_url(owner.slug)
      end
    end
  end

  def ip_allowlist_owner_emails(owner)
    case owner
    when Business
      owner.owners.map { |u| user_email(u) }.compact.uniq
    when Organization
      admin_emails(owner)
    when Integration
      if owner.owner.organization?
        org = owner.owner
        this_app_manager_ids = Permissions::Enumerator.actor_ids_with_permission(action: :manage_app, subject_id: owner.id)
        all_app_manager_ids = Permissions::Enumerator.actor_ids_with_permission(action: :manage_all_apps, subject_id: org.id)
        owner_ids = Permissions::Enumerator.actor_ids_with_permission(action: :own_organization, subject_id: org.id)
        them = org.members(actor_ids: owner_ids + all_app_manager_ids + this_app_manager_ids)
        them.map { |u| user_email(u) }.compact.uniq
      elsif owner.owner.is_a?(User)
        [user_email(owner.owner)]
      end
    end
  end
end
