# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::TrialsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :business_required, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    filter = trials_params[:filter].to_h.presence || HashWithIndifferentAccess.new
    businesses = Business.for_query(params[:query])
    businesses = businesses.order(created_at: filter[:created].to_sym) if filter[:created].present?
    businesses = businesses.order(trial_expires_at: filter[:expires].to_sym) if filter[:expires].present?
    businesses = businesses.order(trial_completed_at: filter[:converted].to_sym) if filter[:converted].present?
    businesses = businesses.order(trial_completed_at: filter[:cancelled].to_sym) if filter[:cancelled].present?

    if filter[:owned_by].present?
      staff = filter[:owned_by] == "staff"
      businesses = businesses.is_staff_owned(staff)
    end

    if filter[:organization_upgraded].present?
      organization_upgraded = filter[:organization_upgraded] == "upgraded"
      businesses =
        if organization_upgraded
          businesses.where.not(upgraded_from: nil)
        else
          businesses.where(upgraded_from: nil)
        end
    end

    if filter[:seat_type].present?
      metered = filter[:seat_type] == "metered"
      businesses =
        if metered
          businesses.metered_ghe
        else
          businesses.volume_ghe
        end
    end

    if filter[:enterprise_type].present?
      emu = filter[:enterprise_type] == "enterprise_managed"
      business_type = emu ? Business.business_types[:enterprise_managed] : Business.business_types[:default_managed]

      businesses = businesses.where(business_type: business_type)
    end

    if filter[:trial_type].present?
      dfd_trial = filter[:trial_type] == "dfd"
      businesses =
        if dfd_trial
          businesses.where(dfd_trial: true)
        else
          businesses.where(dfd_trial: false)
        end
    end

    @trial_active = businesses.trial_active
    @trial_expired = businesses.trial_expired
    @trial_converted = businesses.trial_converted
    @trial_cancelled = businesses.trial_cancelled

    render "stafftools/businesses/trials_list", layout: "stafftools", locals: {
      active_trials: @trial_active
        .paginate(page: current_page(:active_page), per_page: DEFAULT_PAGE_SIZE),
      expired_trials: @trial_expired
        .paginate(page: current_page(:expired_page), per_page: DEFAULT_PAGE_SIZE),
      converted_trials: @trial_converted
        .paginate(page: current_page(:converted_page), per_page: DEFAULT_PAGE_SIZE),
      cancelled_trials: @trial_cancelled
        .paginate(page: current_page(:cancelled_page), per_page: DEFAULT_PAGE_SIZE),
      filter: filter,
      query: params[:query],
      tab: params[:tab] || "active",
    }
  end

  def update
    case params[:operation].to_s
    when "cancel"
      this_business.end_advanced_security_trial_without_purchasing_now(
        actor: current_user,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
        is_stafftools_action: true,
      )
      this_business.cancel_trial(current_user)
      flash[:notice] = "Cancelled the trial for the #{this_business.name} enterprise."
      redirect_to stafftools_enterprise_path(this_business)
    when "convert"
      if this_business.orphaned_organizations.any?
        flash[:error] = "All organizations within the #{this_business.name} enterprise must have \
          an owner before the the trial can be upgraded.".squish
      else
        this_business.end_advanced_security_trial_without_purchasing_now(
          actor: current_user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
          is_stafftools_action: true,
        )
        this_business.convert_trial(current_user, staff_initiated: true, switch_billing_to_invoice: true)
        flash[:notice] = "Upgraded the trial for the #{this_business.name} enterprise to full account."
      end
      redirect_to stafftools_enterprise_path(this_business)
    when "expire"
      this_business.end_advanced_security_trial_without_purchasing_now(
        actor: current_user,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
        is_stafftools_action: true,
      )
      this_business.expire_trial(current_user)
      flash[:notice] = "Expired the trial for the #{this_business.name} enterprise."
      redirect_to stafftools_enterprise_path(this_business)
    when "extend"
      if this_business.extend_trial(current_user)
        in_words = helpers.pluralize(::Billing::EnterpriseCloudTrial.trial_length.in_days.to_i, "day")
        flash[:notice] = \
          "The trial for the #{this_business.name} enterprise has been extended by #{in_words}."
      else
        flash[:error] = "Failed to extend the trial for the #{this_business.name} enterprise."
      end
      redirect_to stafftools_enterprise_path(this_business)
    when "reset"
      if this_business.reset_trial(current_user)
        flash[:notice] = "The #{this_business.name} enterprise trial period has been reset."
      else
        flash[:error] = "Failed to reset trial period for the #{this_business.name} enterprise."
      end
      redirect_to stafftools_enterprise_path(this_business)
    else
      raise RuntimeError, %Q[Unsupported operation param provided: "#{params[:operation]}"]
    end
  end

  private

  def trials_params
    params.permit(:query, :active_page, :expired_page, :converted_page, :cancelled_page, :tab,
      filter: [:owned_by, :seat_type, :enterprise_type, :created, :expires, :converted, :cancelled, :organization_upgraded, :trial_type])
  end
end
