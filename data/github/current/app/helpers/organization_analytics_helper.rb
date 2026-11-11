# typed: true
# frozen_string_literal: true

module OrganizationAnalyticsHelper
  include HydroHelper
  include AnalyticsHelper
  include ApplicationHelper

  extend T::Helpers

  abstract!

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def params; end

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  module OrganizationsNew
    FREE_PLAN_CARD = :FREE_PLAN_CARD
    TEAM_PLAN_CARD = :TEAM_PLAN_CARD
    ENTERPRISE_PLAN_CARD = :ENTERPRISE_PLAN_CARD
    REVIEW_SUBSCRIPTION_PLANS = :REVIEW_SUBSCRIPTION_PLANS
    ENTERPRISE_PLAN_CARD_CONTACT_LINK = :ENTERPRISE_PLAN_CARD_CONTACT_LINK
    COMPANY_OWNED = :COMPANY_OWNED
  end

  REFERRAL_KEYS = %i(ref_page ref_cta ref_loc)

  def ga_label_with_analytics_tracking_id(ga_string, organization: nil)
    ga_string += ";" if ga_string.last != ";"

    meta_label = "meta: user_id: #{current_user&.analytics_tracking_id}"
    meta_label += ";org_id: #{organization.analytics_tracking_id}" if organization
    meta_label += referral_meta_labels

    "#{ga_string} #{meta_label}"
  end

  def organization_referral_params(additional_params: {})
    params.permit(*T.unsafe(REFERRAL_KEYS)).reject { |_k, v| v.blank? }.merge(additional_params)
  end

  def organization_new_free_plan_card_data_attributes
    hydro_attributes = organization_new_hydro_click_tracking_attributes(
      target: OrganizationsNew::FREE_PLAN_CARD,
    )

    { "ga-change" => "New pricing, select product, Free;" }
      .merge(hydro_attributes)
  end

  def organization_new_team_plan_card_data_attributes
    hydro_attributes = organization_new_hydro_click_tracking_attributes(
      target: OrganizationsNew::TEAM_PLAN_CARD,
    )

    {
      "ga-change" => "New pricing, select product, Team;",
      "ga-ec" => JSON.dump([
        ["ec:addProduct", { name: "Team", position: 2 }],
        ["ec:setAction", "click", { list: "Signup" }],
      ]),
    }.merge(hydro_attributes)
  end

  def organization_new_enterprise_plan_card_data_attributes
    hydro_attributes = organization_new_hydro_click_tracking_attributes(
      target: OrganizationsNew::ENTERPRISE_PLAN_CARD,
    )

    {
      "ga-change" => "New pricing, select product, Business;",
      "ga-ec" => JSON.dump([
        ["ec:addProduct", { name: "Business", position: 3 }],
        ["ec:setAction", "click", { list: "Signup" }],
      ]),
    }.merge(hydro_attributes)
  end

  def organization_new_enterprise_server_contact_data_attributes
    hydro_attributes = organization_new_hydro_click_tracking_attributes(
      target: OrganizationsNew::ENTERPRISE_PLAN_CARD_CONTACT_LINK,
    )

    { "ga-click" => ga_label_with_analytics_tracking_id("Signup funnel select org plan, click, text:Contact our team;") }
      .merge(hydro_attributes)
  end

  def enterprise_plan_cloud_data_attributes
    tracking_attributes = {
      category: "Start Enterprise Cloud",
      action: "Pick Enterprise Cloud",
      label: "ref_cta:Enterprise Cloud;ref_loc:enterprise_plan"
    }

    hydro_click_tracking_attributes("create_org.click", tracking_attributes).merge(analytics_click_attributes(**tracking_attributes))
  end

  def enterprise_plan_server_data_attributes
    analytics_click_attributes(
      category: "Start Enterprise Server",
      action: "Pick Enterprise Server",
      label: "ref_cta:Enterprise Server;ref_loc:enterprise_plan"
    )
  end

  def organization_plan_comparison_data_attributes(text:)
    {
      "ga-click" => ga_label_with_analytics_tracking_id("Organization plan pricing comparison,click,text:#{text};"),
    }.merge(test_selector_hash("organization-plan-pricing-comparison-button"))
  end

  private

  def referral_meta_labels
    return unless defined?(:params)

    meta_label = ""
    meta_label += ";ref_page:#{params[:ref_page]}" if params.has_key?(:ref_page)
    meta_label += ";ref_cta:#{params[:ref_cta]}" if params.has_key?(:ref_cta)
    meta_label += ";ref_loc:#{params[:ref_loc]}" if params.has_key?(:ref_loc)

    meta_label
  end

  # Provide a wrapper around the standard organiztion_new parameters sent to hydro for analytics
  #
  # event_context - symbol representing the context for the event to be sent to hydro
  # target -  symbol representing the event
  #
  # Returns a Hash
  def organization_new_hydro_click_tracking_attributes(target:)
    hydro_click_tracking_attributes(
      "organization.new.click",
      target: target,
      user_id: current_user&.id,
    )
  end
end
