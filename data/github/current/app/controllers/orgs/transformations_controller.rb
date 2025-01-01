# typed: true
# frozen_string_literal: true

class Orgs::TransformationsController < ApplicationController
  include OrganizationsControllerMethods

  before_action :login_required, except: :show
  before_action only: :create do
    T.bind(self, Orgs::TransformationsController)
    check_trade_compliance(redirect_url: settings_organizations_url)
  end
  after_action :customer_category_instrumentation

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:show]

  javascript_bundle "signup"
  javascript_bundle "organizations"

  stylesheet_bundle :signup

  # Transforms the currently logged in user into an organization. Yikes.
  def create
    GitHub.dogstats.increment("organization", tags: ["action:transform"])

    if current_user.is_enterprise_managed?
      flash[:error] = "You cannot transform this account into an organization because this account is managed by your enterprise."
      return redirect_to settings_organizations_url
    end

    # Prevent transforms for plan specific coupons
    if current_user.has_a_plan_specific_coupon?
      flash[:error] = "You cannot transform this account into an organization because you have an active coupon that is locked to a plan. Please contact support."
      return redirect_to settings_organizations_url
    end

    # Prevent transform when sponsoring
    if current_user.actively_sponsoring?
      flash[:error] = "You cannot transform this account into an organization because active sponsorships must be " \
        "cancelled first."
      return redirect_to settings_organizations_url
    end

    if current_user.active_sponsors_account?
      flash[:error] = "You cannot transform this account into an organization because you have an active GitHub Sponsors account."
      return redirect_to settings_organizations_url
    end

    # First convert the array of string user names into user objects.
    if !params[:organization]
      flash.now[:error] = "No owners or emails were submitted."
      return render_new_organization
    end

    if current_user.organizations.any?
      flash[:error] = "You cannot transform this account into an organization before leaving all other organizations first."
      return redirect_to settings_organizations_url
    end

    if GitHub.billing_enabled?
      plan = org_hash[:plan] ||= params[:plan]
      unless GitHub::Plan.find(plan).try(:org_plan_or_per_seat?)
        flash.now[:error] = "Please choose a valid plan."
        return render_new_organization
      end
    else
      plan = org_hash[:plan] = "enterprise"
    end

    if helpers.has_payment_details?
      if current_user.has_billing_record?
        result = GitHub::Billing.update_payment_method(current_user, helpers.payment_details)
      else
        result = GitHub::Billing.create_customer(current_user, helpers.payment_details, actor: current_user)
      end
      unless result.success?
        flash[:error] = result.error_message.to_s
        return render_new_organization
      end
    end

    org_hash.delete(:login)
    admin_logins = org_hash.delete(:admin_logins) || []
    owner        = User.find_by_login(admin_logins.first) if admin_logins.any?
    org          = Organization.new(org_hash)

    old_seats_count = owner&.seats
    old_plan_name = owner&.plan&.name

    # Prevent transforming the org when the owner would be someone who has blocked the current user
    # See: https://github.com/github/search-and-flywheel/issues/222
    if current_user.blocked_by?(owner)
      # Message should be generic so we don't reveal the current user is blocked by the submitted owner
      flash[:error] = "You cannot transform this account into an organization right now."
      return redirect_to settings_organizations_url
    end

    if !current_user.needs_valid_payment_method_to_switch_to_plan?(plan)
      Organization.transform(current_user, owner, org_hash.to_hash)
      helpers.publish_billing_plan_changed_for(
        actor: current_user,
        user: owner,
        old_seat_count: old_seats_count,
        new_seat_count: org.seats,
        old_plan_name: old_plan_name,
        new_plan_name: plan,
      )
      reset_session
      cookies[:org_transform_notice] = { value: Base64.strict_encode64("Please sign in as #{owner.display_login}, the owner of your new #{current_user.safe_profile_name} organization."),
                                         expires: 1.hour.from_now, secure: request && request.ssl?, domain: cookie_domain }
      render "organizations/transform/transforming"
    else
      @current_organization = org
      flash[:error] = "Please provide a credit card to switch to the #{plan.capitalize} plan."
      render_new_organization
    end
  rescue Organization::TransformationFailed => e
    flash.now[:error] = e.to_s
    render_new_organization
  end

  # Responds to the poll-include-fragment element ajax request, indicating
  # whether the user is currently transforming or not.
  def show
    user = User.find_by_login(params[:user])
    return head 404 if user.nil?

    if Organization.transforming?(user)
      head 202
    else
      head 200
    end
  end

  private

  def current_organization
    helpers.current_organization
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_organization # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_organization
  end
end
