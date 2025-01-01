# typed: false
# frozen_string_literal: true

module ConditionalAccessHelper

  # Populate the error flash with the correspondent policy message if a
  # PlatformHelper::ConditionalAccessError is raised from within the block.
  #
  # Raises the input error in local development if it's not a supported policy.
  def populate_flash_on_cap_error(&block)
    yield
  rescue PlatformHelper::ConditionalAccessError => e
    case e
    when PlatformHelper::IpAllowListError
      flash[:error] = "You must connect from an allowed IP address"
    when PlatformHelper::SamlError
      flash[:error] = "You must authenticate via SAML SSO"
    when PlatformHelper::EmuOwnershipError
      flash[:error] = "Enterprise managed users can only perform operations within their owning enterprise"
    when PlatformHelper::ExternalConditionalAccessPolicyError
      flash[:error] = "Access has been blocked by Conditional Access Policies defined in your identity provider. Please contact your identity provider administrator for more information"
    else
      raise_or_report(e)
      flash[:error] = "Uh oh! Something went wrong"
    end
  end

  # Return url and contextual policy message to display if a user doesn't meet CAP requirements.
  #
  # target          - ::Business and/or ::Organization instance
  # policy          - Conditional Access Policy(CAP) symbol. options: :saml, :ip_allowlist. Full list here: ConditionalAccess::Web::Filter#conditional_access_policies
  # resource_label  - Name of the resource being viewed i.e repositories, codespaces
  # return_to       - url to redirect_to. default: ""
  # join_word       - word to join the resulting sentence. default: "within"
  def restricted_policy_link(target, policy:, resource_label:, return_to: "", join_word: "within")
    link_or_label = restricted_path(policy, target, return_to)

    case target
    when ::Business
      safe_join \
        [
          link_or_label,
          "to see #{resource_label} for accounts #{join_word} the",
          content_tag(:strong, target.name),
          "enterprise."
        ],
        " "
    when ::Organization
      safe_join \
        [
          link_or_label,
          "to see #{resource_label} #{join_word} the",
          content_tag(:strong, target.display_login),
          "organization."
        ],
        " "
    end
  end

  # Replaces Business-owned Organizations and Users with their Business in the return value.
  #
  # Included as part a bug fix described here: https://github.com/github/github/pull/155282
  def target_for(unauthorized_accounts, policy)
    emu_business = nil
    unauthorized_accounts.map do |account|
      case policy.to_sym
      when :saml
        account.is_a?(Organization) && account.sso_enabled_on_business? ? account.business : account
      when :ip_allowlist
        if account.is_a?(Organization) && account.ip_allowlist_enabled_on_business?
          account.business
        # IP allow list user-level filtering:
        elsif account.is_a?(User) && account.is_enterprise_managed?
          # Avoid looking up User#enterprise_managed_business for every EMU passed
          # in unauthorized_accounts
          if emu_business.present?
            emu_business
          else
            emu_business = account.enterprise_managed_business
          end
        else
          account
        end
      when :two_factor
        account.is_a?(Organization) && account.two_factor_enabled_on_business? ? account.business : account
      when :external_conditional_access_policy
        emu_account = if account.is_a?(User) && account.is_enterprise_managed?
          # Avoid looking up User#enterprise_managed_business for every EMU passed
          # in unauthorized_accounts
          if emu_business.present?
            emu_business
          else
            emu_business = account.enterprise_managed_business
          end
        elsif account.is_a?(Organization) && account.enterprise_managed_user_enabled?
          if emu_business.present?
            emu_business
          else
            emu_business = account.business
          end
        # at this point just return the account, it could be business, organization or a user
        else
          account
        end
        emu_account if emu_account&.feature_enabled?(:idp_cap_for_web)
      else
        raise ArgumentError, "unknown policy #{policy}"
      end
    end.compact.uniq
  end

  private

  # Generates url and/or contextual string to guide users on how to solve the Conditional Access Policy violation.
  #
  # Return url/string
  def restricted_path(policy, target, return_to)
    path = restricted_raw_path(policy, target, return_to)
    if path.nil?
      policy_satisfy_criteria_label(policy)
    else
      link_to(policy_satisfy_criteria_label(policy), path, class: "Link--inTextBlock")
    end
  end

  def restricted_raw_path(policy, target, return_to)
    case policy.to_sym
    when :saml
      if target.is_a?(Business)
        business_idm_sso_enterprise_path(target, return_to: return_to)
      else
        org_idm_sso_path(target, return_to: return_to)
      end
    when :two_factor
      settings_user_2fa_intro_path
    when :ip_allowlist
      # No path required for IP Allowlist
      nil
    when :external_conditional_access_policy
      # No path required for external conditional access policy
      nil
    else
      nil
    end
  end

  def policy_satisfy_criteria_label(policy)
    case policy.to_sym
    when :saml
      "Single sign-on"
    when :two_factor
      "Enable 2FA"
    when :ip_allowlist
      "Connect from an allowed IP address"
    when :external_conditional_access_policy
      "Conditional Access Policy managed by your Identity Provider"
    else
      raise ArgumentError, "unknown policy #{policy}"
    end
  end

  def raise_or_report(e)
    raise e if Rails.env.test? || Rails.env.development?
    Failbot.report!(e)
  end
end
