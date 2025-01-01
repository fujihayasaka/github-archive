# typed: true
# frozen_string_literal: true

module MailchimpTeamListHelper
  TARGET_COUNTRIES = ["US"]
  FREE_ORG_ACCOUNT_AGE_MIN = 30.days

  # Returns Boolean
  # Checks if we should subscribe user to the team list
  # Any current plan we offer should be subscribed
  def subscribe_to_team_list?(user:, org:)
    NewsletterPreference.marketing?(user: user) &&
    (org.plan.business? || org.plan.business_plus? || org.plan.free?)
  end

  # Returns Boolean
  # Checks if we should enroll user in the team admin onboarding campaign
  def start_team_admin_onboarding?(user:, org:)
    org.adminable_by?(user) &&
      in_target_country?(user.most_recent_session) &&
      org.plan.business? &&
      !already_subscribed?(user) &&
      !admin_for_other_team?(user, org)
  end

  # Returns Boolean
  # Checks if user is an admin of any other team org
  def admin_for_other_team?(user, org)
    user.owned_organizations.reject { |o| o == org }.pluck(:plan).include?(GitHub::Plan.business.name)
  end

  # Returns Boolean
  # Checks if user is already in the campaign
  def already_subscribed?(user)
    Onboarding.for(user).enrolled_in_team_admin_onboarding_series?
  end

  # Returns Boolean
  # Checks if user's last session was in a target country
  def in_target_country?(user_session)
    return false unless user_session.present?

    TARGET_COUNTRIES.any? { |country_code| user_session.from_country?(country_code) }
  end

  # Returns Boolean
  # Checks if plan is present in set of user orgs
  def active_for_plan?(plan, org_plans)
    org_plans.include?(plan)
  end

  def user_merge_fields(user, org)
    user.reload
    user_org_plans = user.organizations.pluck(:plan)
    user_admin_plans = user.owned_organizations.pluck(:plan)
    fields = {
      user: user,
      org: org,
      active_admin: active_for_plan?(GitHub::Plan.business.name, user_admin_plans),
      active_user: active_for_plan?(GitHub::Plan.business.name, user_org_plans),
      active_ghec_admin: active_for_plan?(GitHub::Plan.business_plus.name, user_admin_plans),
      active_ghec_user: active_for_plan?(GitHub::Plan.business_plus.name, user_org_plans),
      active_free_admin: user_has_min_account_age?(user) && active_for_plan?(GitHub::Plan.free.name, user_admin_plans),
      active_free_user: user_has_min_account_age?(user) && active_for_plan?(GitHub::Plan.free.name, user_org_plans),
    }

    if set_free_org_for_admin_campaign?(user: user, org: org)
      fields.merge!({
        free_org_for_admin_campaign: org,
        free_org_for_admin_campaign_at: Time.current.to_s,
        free_org_for_admin_campaign_active: true
      })
      mark_free_org_for_admin_campaign_set(user: user, org: org)
    elsif update_free_org_for_admin_campaign_active?(user: user, org: org)
      free_org_for_admin_campaign_id = Organization::KV.store.get(free_org_for_admin_campaign_key(user)).value!.to_i
      # is user still an admin of the free org we used for the campaign
      fields[:free_org_for_admin_campaign_active] = user.owned_organization_ids.include?(free_org_for_admin_campaign_id)
    end

    fields
  end

  def set_free_org_for_admin_campaign?(user:, org:)
    # we haven't already set the field previously
    !Organization::KV.store.exists(free_org_for_admin_campaign_key(user)).value! &&
      # a free org triggered this update
      org.plan.free? &&
      # user is an admin of the org
      org.adminable_by?(user) &&
      # user must be certain account age
      user_has_min_account_age?(user)
  end

  def update_free_org_for_admin_campaign_active?(user:, org:)
    # key must exists so we know the free_org_for_admin_campaign field has been set and free org triggered this update
    Organization::KV.store.exists(free_org_for_admin_campaign_key(user)).value! && org.plan.free?
  end

  def mark_free_org_for_admin_campaign_set(user:, org:)
    ActiveRecord::Base.connected_to(role: :writing) do
      Organization::KV.store.setnx(free_org_for_admin_campaign_key(user), org.id.to_s)
    end
  end

  def free_org_for_admin_campaign_key(user)
    "free_org_for_admin_campaign_mailchimp_field_set_for_#{user.id}"
  end

  # For free orgs we to set the field to true in mailchimp once they reach a minimum account age
  def user_has_min_account_age?(user)
    Date.today >= user.created_at + FREE_ORG_ACCOUNT_AGE_MIN
  end
end
