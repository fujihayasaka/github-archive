# typed: true
# frozen_string_literal: true

class Customers::BillingController < ApplicationController
  extend T::Sig

  include ApplicationController::VerifiedFetchDependency
  include BillingSettingsHelper
  include Billing::Platform::Api::Utils
  include Businesses::Concerns::BusinessAccess
  include GitHub::Memoizer
  include OrganizationsHelper
  include ReactHelper

  T.unsafe(self).react_bundle_name = "billing-app"

  stylesheet_bundle :billing

  before_action :ensure_actor_access
  before_action :ensure_vnext_enabled

  depends_on_clusters ApplicationRecord::Billing,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::Copilot,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Repositories,
                      only: [:show]

  def show
    begin
      notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_entity, actor: current_user)
      banners = notification.budget_threshold_banners(actor: T.must(current_user))
    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      GitHub.dogstats.increment("billing_platform.budget_banner_error")
      banners = []
    end

    render_react_app(
      payload: {
        customer: customer_payload(this_entity),
        customer_selections: usage_customer_selections(this_entity),
        period_selections: usage_period_selections,
        admin_roles: admin_roles(this_business),
        enabled_products: enabled_products,
        budget_alert_details: banners.map do |banner|
          {
            text: banner.text,
            variant: banner.variant.to_s,
            dismissable: banner.dismissible?,
            dismiss_link: banner.dismissal_path,
            budget_id: banner.budget_uuid,
          }
        end
      },
      page_data: { selected_link: :billing_vnext_overview },
      title: "Billing Overview",
      layout: customer_billing_page_layout,
      ssr: true
    )
  end

  private

  sig { returns(::Billing::Types::Account) }
  memoize def this_entity
    return this_business if enterprise_path?
    return this_organization if organization_path?
    this_user
  end
  helper_method :this_entity

  memoize def this_organization
    Organization.find_by(login: params[:organization_id])
  end
  alias_method :current_organization, :this_organization

  memoize def this_user
    current_user
  end
  helper_method :this_user

  def target_for_conditional_access
    return this_business if enterprise_path? && this_business
    return this_organization if organization_path? && this_organization
    return this_user if individual_path? && this_user
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    # Should this happen it will raise ArgumentError: malformed request
  end

  def customer_billing_page_layout
    return "layouts/react_business" if enterprise_path?
    return "layouts/organization_settings" if organization_path?
    "layouts/user_settings"
  end

  def usage_filter_params
    params.except(:organization_id, :enterprise_slug).permit(:customer_id, :period, :product, :query, :group).to_h.symbolize_keys
  end

  def ensure_actor_access
    return render_404 unless logged_in?
    return business_access_required(allow_org_owners: true) if enterprise_path?
    return render_404 if organization_path? && !org_billing_manageable?(this_organization)
  end

  def ensure_vnext_enabled
    unless this_entity.customer&.billed_via_billing_platform?
      redirect_to :settings_user_billing
    end
  end

  # The GraphQL query that powers the Repository picker enforces CAP filtering and we need to prompt the user
  # to authenticate in order to see all of their repositories. Only Org owners are able to set budgets and cost centers
  # on repositories which is why we limit the viewer role to "owner".
  memoize def set_organizations
    @organizations = this_business.nil? ? [] : this_business.filtered_organizations(viewer: current_user, viewer_role: "owner")
  end

  memoize def enterprise_path?
    T.must(request).path.start_with?("/enterprises/")
  end

  memoize def organization_path?
    T.must(request).path.start_with?("/organizations/")
  end

  memoize def individual_path?
    T.must(request).path.start_with?("/settings/")
  end

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def all_products
    products_response = billing_platform_client.get_all_products
    products = if products_response.is_a?(::Billing::Platform::Api::Error)
      []
    else
      products_response[:products]
    end
    products
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products
    enabled_products = this_entity.customer&.products_billed_via_billing_platform
    # enabled_products is an array of strings, so we need to get all products from bp since we need friendly names for the UI
    all_products.select { |product| enabled_products&.include?(product[:name]) }
  end

  sig { returns(T::Boolean) }
  def is_org?
    this_entity.is_a?(Organization)
  end

  sig { returns(String) }
  def react_layout
    is_org? ? "organization_settings" : "user_settings"
  end
end
