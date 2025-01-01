# typed: true
# frozen_string_literal: true

module VerifiableDomainsHelper
  include BusinessesHelper
  include Kernel

  # Public: Get the page info hash given a domain owner.
  #
  # owner - Business or Organization that can own domains
  #
  # Returns Hash
  def verifiable_domains_page_info_hash(owner)
    page_info_hash = {
      title: "Verified & approved domains",
      selected_link: :verified_approved_domains,
    }
    if owner.instance_of?(Business)
      page_info_hash[:selected_link] = :business_domains_settings
      page_info_hash[:sidebar] = :settings
      page_info_hash[:stafftools] = T.unsafe(self).stafftools_enterprise_path(owner)
    end
    page_info_hash
  end

  # Public: Get the introduction description text to be used for the verifiable
  # domains page for a domain owner.
  #
  # owner - Business or Organization that can own domains
  # verified_tag - String HTML tag
  #
  # Returns String
  def verifiable_domains_owner_description(owner, verified_tag)
    text_part1 = if owner.instance_of?(Business)
      "You can verify the domains controlled by your enterprise's organizations \
        to confirm the identities of the organizations that belong to your enterprise on GitHub. A".squish
    else
      "You can verify the domains controlled by your organization to confirm \
        your organization's identity on GitHub. A".squish
    end

    text_part2 = if owner.instance_of?(Business)
      "badge will be added to the profile page of each organization within the enterprise, \
        if all of the domains displayed on its profile (e.g. public email or website URL) are verified.".squish
    else
      "badge will be added to your organization's profile page if all of the domains displayed on \
        your profile (e.g. public email or website URL) are verified.".squish
    end

    approved_text_part1 = "You may also approve a domain by first adding it to the list of \
                          eligible domains. Approved domains".squish
    approved_text_part2 = "may be used for email notification routing to users with verified emails that \
                          do not belong to a domain that you can verify.".squish
    approved_text = [approved_text_part1, " ", approved_text_part2, " "]

    help_link = T.unsafe(self).link_to \
      "Learn more about verifying or approving a domain for your enterprise.",
      verifiable_domains_help_url(owner),
      class: "Link--inTextBlock"

    safe_join([
      text_part1, " ", verified_tag, " ",
      text_part2, " ", approved_text, help_link
    ].flatten)
  end

  def verifiable_domains_help_url(owner)
    if owner.instance_of?(Business)
      if GitHub.enterprise?
        "#{GitHub.help_url}/admin/configuration/configuring-your-enterprise/verifying-or-approving-a-domain-for-your-enterprise"
      else
        "#{GitHub.help_url}/github/setting-up-and-managing-your-enterprise/verifying-or-approving-a-domain-for-your-enterprise-account"
      end
    else
      "#{GitHub.help_url}/organizations/managing-organization-settings/verifying-or-approving-a-domain-for-your-organization"
    end
  end

  # Public: Should we render notification restrictions for verifiable domains?
  #
  # owner - Business or Organization that can own domains
  #
  # Returns Boolean
  def show_verifiable_domains_notification_restrictions?(owner)
    return false if owner.respond_to?(:plan_supports?) &&
      !owner.plan_supports?(:restrict_notification_delivery)

    VerifiableDomain.usable_for(owner).verified_or_approved.any?
  end

  # Public: Are verifiable domains notification restrictions enabled by policy
  # for the given owner?
  #
  # owner - Business or Organization that can own domains
  #
  # Returns Boolean
  def verifiable_domains_notification_restrictions_enabled_by_policy?(owner)
    !owner.instance_of?(Business) && owner.restrict_notifications_to_verified_domains_policy?
  end

  # Public: Should we render the notification restriction confirmation for a
  # given owner?
  #
  # owner - Business or Organization that can own domains
  #
  # Returns Boolean
  def render_verifiable_domain_notification_restriction_confirmation?(owner)
    !owner.restrict_notifications_to_verified_domains? &&
      owner.members_without_eligible_email.any?
  end

  # Public: Get the owner path for a specific action.
  #
  # action - Symbol representing the action (default :index)
  # owner - Business or Organization representing the owner in request context
  # domain - The VerifiableDomain
  #
  # Returns String
  def owner_domain_path_for_action(action: :index, owner:, domain: nil)
    domain_owner = domain&.owner || owner
    params = [domain_owner.to_param]
    params += [domain.id] unless domain.blank?
    owner_domains_paths_hash[action][domain_owner.class].call(params)
  end

  def notification_restrictions_path_for(owner)
    case owner
    when Business
      T.unsafe(self).enterprise_notification_restrictions_path(owner)
    when Organization
      T.unsafe(self).org_notification_restrictions_path(owner)
    end
  end

  private

  def owner_domains_paths_hash
    @paths_hash ||= {
      index: {
        Organization => lambda { |params| settings_org_domains_path(*params) },
        Business => lambda { |params| settings_enterprise_domains_enterprise_path(*params) }
      },
      new: {
        Organization => lambda { |params| new_org_domain_path(*params) },
        Business => lambda { |params| new_enterprise_domain_path(*params) }
      },
      create: {
        Organization => lambda { |params| org_domains_path(*params) },
        Business => lambda { |params| enterprise_domains_path(*params) }
      },
      destroy: {
        Organization => lambda { |params| org_domain_path(*params) },
        Business => lambda { |params| enterprise_domain_path(*params) }
      },
      verification_steps: {
        Organization => lambda { |params| verification_steps_org_domain_path(*params) },
        Business => lambda { |params| verification_steps_enterprise_domain_path(*params) }
      },
      regenerate_token: {
        Organization => lambda { |params| regenerate_token_org_domain_path(*params) },
        Business => lambda { |params| regenerate_token_enterprise_domain_path(*params) }
      },
      verify: {
        Organization => lambda { |params| verify_org_domain_path(*params) },
        Business => lambda { |params| verify_enterprise_domain_path(*params) }
      },
      approve: {
        Organization => lambda { |params| approve_org_domain_path(*params) },
        Business => lambda { |params| approve_enterprise_domain_path(*params) }
      }
    }
  end
end
