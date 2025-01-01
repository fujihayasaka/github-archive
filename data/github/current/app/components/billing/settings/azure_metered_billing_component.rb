# typed: strict
# frozen_string_literal: true

class Billing::Settings::AzureMeteredBillingComponent < ApplicationComponent
  extend T::Sig

  sig { returns(T.untyped) }
  attr_reader :view

  sig { returns(Billing::Types::OrgOrBusiness) }
  attr_reader :target

  sig do
    params(
      view: T.untyped,
      target: Billing::Types::OrgOrBusiness,
      subscription_will_auto_enable: T::Boolean,
      redirect_path: T.nilable(String)
    ).void
  end
  def initialize(view:, target:, subscription_will_auto_enable: false, redirect_path: nil)
    @view = view
    @target = target
    @subscription_will_auto_enable = subscription_will_auto_enable
  end

  sig { returns(T::Boolean) }
  def has_azure_token?
    client.has_token?
  end

  sig { returns(T::Boolean) }
  def has_azure_subscription?
    linked_azure_subscription.present?
  end

  sig { returns(T::Boolean) }
  def subscription_will_auto_enable?
    @subscription_will_auto_enable
  end

  sig { returns(T.nilable(String)) }
  def linked_azure_subscription
    target.customer&.azure_subscription_id
  end

  sig { returns(String) }
  def linked_azure_subscription_name
    target.customer&.azure_subscription_name || "Subscription"
  end

  sig { returns(T.nilable(T::Boolean)) }
  def invalid_azure_subscription_detected?
    target.customer&.invalid_azure_subscription_detected? || false
  end

  sig do
    params(
      explicit_tenant_selected: T::Boolean,
      tenant: String,
    ).returns(URI::HTTPS)
  end
  def azure_subscription_uri(explicit_tenant_selected: false, tenant: "common")
    uri = URI("https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/authorize")

    state_encoded = state_hash(explicit_tenant_selected: explicit_tenant_selected)

    uri.query = URI.encode_www_form({
      client_id: GitHub.azure_oauth_app_id,
      redirect_uri: redirect_uri,
      scope: "https://management.azure.com/user_impersonation",
      response_type: "code",
      state: state_encoded,
      response_mode: "query",
      prompt: "select_account"
    })

    T.cast(uri, URI::HTTPS)
  end

  sig { returns(T::Boolean) }
  def metered_billing_enabled?
    target.metered_via_azure?
  end

  sig { returns(String) }
  def account_id
    target = self.target
    return target.slug if target.is_a?(Business)

    target.display_login
  end

  sig { returns(Symbol) }
  def account_type
    return :enterprise if target.is_a?(Business)

    :organization
  end

  sig { returns(String) }
  def form_action_path
    case target = self.target
    when Organization
      azure_linked_subscriptions_path(account_type: "organization", account_id: target.display_login)
    when Business
      billing_settings_selected_azure_subscription_path(target.slug)
    else
      T.absurd(target)
    end
  end

  private

  sig { params(explicit_tenant_selected: T::Boolean).returns(String) }
  def state_hash(explicit_tenant_selected: false)
    target = self.target
    hash = if target.is_a?(Business)
      {
        business_slug: target.slug,
        explicit_tenant_selected: explicit_tenant_selected,
      }
    else
      {
        org_login: target.display_login,
        explicit_tenant_selected: explicit_tenant_selected
      }
    end

    if business? && GitHub.multi_tenant_enterprise?
      # We pass the host name with tenant so the Azure redirects will work in Proxima where customers have custom subdomains
      hash[:host_name] = GitHub.host_name_with_tenant
    end
    Base64.encode64(hash.to_json)
  end

  sig { returns(String) }
  def redirect_uri
    return GitHub.azure_oauth_app_redirect_uri_for_businesses if business?

    GitHub.azure_oauth_app_redirect_uri_for_orgs
  end

  sig { returns(T::Boolean) }
  def business?
    !!target.is_a?(Business)
  end

  sig { returns(T::Boolean) }
  def render?
    return true if business?

    !target.plan.legacy?
  end

  sig do
    returns(T.any(
      Billing::Azure::BusinessSubscriptionClient,
      Billing::Azure::OrgSubscriptionClient
    ))
  end
  memoize def client
    target = self.target
    return Billing::Azure::BusinessSubscriptionClient.new(current_user, target) if target.is_a?(Business)

    Billing::Azure::OrgSubscriptionClient.new(current_user, target)
  end
end
