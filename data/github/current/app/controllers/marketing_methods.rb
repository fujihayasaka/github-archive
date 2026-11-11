# typed: strict
# frozen_string_literal: true

module MarketingMethods
  extend T::Helpers

  requires_ancestor { ApplicationController }

  EVENT_TYPES = T.let({
    self_serve: "cloud_trial_upgrade_self_serve",
    sales_serve: "cloud_trial_upgrade_sales_serve",
  }.freeze, { self_serve: String, sales_serve: String })

  sig do
    params(
      success: T::Boolean,
      organization: Organization,
      actor: User,
      is_enterprise_cloud_trial: T::Boolean,
      redirect: T::Boolean,
    ).returns({ category: String, action: String, label: T::Hash[Symbol, T.nilable(String)] })
  end
  def organization_creation_ga_event_attributes(success, organization, actor, is_enterprise_cloud_trial, redirect: true)
    pricing = Billing::Pricing.new(
      plan: organization.plan,
      seats: organization.seats,
      plan_duration: "year",
      coupon: organization.coupon,
    )

    labels = referral_params.compact.merge({
      plan: translate_plan_name(organization.plan),
      type: new_organization_type(organization, is_enterprise_cloud_trial)
    })

    {
      category: "Organization creation",
      action: success ? "Success" : "Failure",
      label: base_organization_ga_label_hash(organization, actor, is_enterprise_cloud_trial, pricing).merge(labels)
    }
  end

  sig do
    params(
      success: T::Boolean,
      organization: User,
      actor: User,
      old_plan_name: T.any(String, GitHub::Plan),
      new_plan_name: T.any(String, GitHub::Plan),
      old_seats: Integer,
      new_seats: Integer,
    ).returns({ category: String, action: String, label: T::Hash[Symbol, T.untyped] })
  end
  def organization_plan_change_ga_event_attributes(success, organization, actor, old_plan_name, new_plan_name, old_seats, new_seats)
    old_plan = GitHub::Plan.find(old_plan_name)
    new_plan = GitHub::Plan.find(new_plan_name)

    new_pricing = Billing::Pricing.new(
      plan: new_plan,
      seats: new_seats,
      plan_duration: "year",
      coupon: organization.coupon,
    )
    old_pricing = Billing::Pricing.new(
      plan: old_plan,
      seats: old_seats,
      plan_duration: "year",
      coupon: organization.coupon,
    )
    transition = new_pricing.annual_recurring_revenue >= old_pricing.annual_recurring_revenue ? "Upgrade" : "Downgrade"
    transition_params = {
      transition: transition,
      currentplan: translate_plan_name(old_plan),
      newplan: translate_plan_name(new_plan),
      oldseats: old_seats,
      newseats: new_seats,
    }

    labels = base_organization_ga_label_hash(organization, actor, false, new_pricing)
      .merge(transition_params)
      .compact

    {
      category: "Change organization",
      action: success ? "Success" : "Failure",
      label: labels,
    }
  end

  sig { params(success: T::Boolean, organization: Organization, actor: User).returns({ category: String, action: String, label: T::Hash[Symbol, T.untyped] }) }
  def organization_trial_extension_ga_event_attributes(success, organization, actor)
    labels = base_organization_ga_label_hash(organization, actor, true)
      .merge({ transition: "ExtendTrial" })
      .compact

    {
      category: "Change organization",
      action: success ? "Success" : "Failure",
      label: labels,
    }
  end

  private

  sig do
    params(
      organization: User,
      actor: User,
      is_enterprise_cloud_trial: T::Boolean,
      pricing: T.nilable(Billing::Pricing),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def base_organization_ga_label_hash(organization, actor, is_enterprise_cloud_trial, pricing = nil)
    {
      orgid: organization.analytics_tracking_id,
      userid: actor.analytics_tracking_id,
      seats: organization.seats,
      discount: is_enterprise_cloud_trial ? 0 : pricing&.discount.to_f,
    }.merge(referral_params).compact
  end

  sig { params(organization: Organization, is_enterprise_cloud_trial: T::Boolean).returns(String) }
  def new_organization_type(organization, is_enterprise_cloud_trial)
    if is_enterprise_cloud_trial
      "trial"
    elsif organization.plan.free?
      "free"
    else
      "paid"
    end
  end

  sig { params(plan: T.nilable(GitHub::Plan)).returns(T.nilable(String)) }
  def translate_plan_name(plan)
    return nil unless plan

    case plan.name
    when "free", "free_with_addons"
      "Free"
    when "business"
      "Team"
    when "business_plus"
      "EnterpriseCloud"
    else
      plan.display_name
    end
  end
end
