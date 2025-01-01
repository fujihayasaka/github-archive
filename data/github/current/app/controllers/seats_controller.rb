# typed: true
# frozen_string_literal: true

class SeatsController < ApplicationController

  include BillingSettingsHelper
  include OrganizationsHelper
  include ActionView::Helpers::TextHelper
  include SeatsHelper
  include MarketingMethods
  include TradeControlsControllerMethods
  include PlanDowngradeHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :redirect_if_business_owned, except: [:trade_screening_update, :show]
  before_action do
    T.bind(self, SeatsController)
    check_trade_compliance(target: target)
  end

  before_action :ensure_per_seat_plan, except: [:switch, :trade_screening_update]
  before_action :ensure_downgradable, only: [:remove_seats]
  before_action :ensure_not_enterprise_or_invoiced, only: [:show]
  before_action :use_available_pending_plan_change, only: [:remove_seats]
  before_action :seat_change, only: [:show, :remove_seats, :update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:remove_seats]

  def show
    url = org_seats_path(target, seats: seat_delta, return_to: params[:return_to])

    respond_to do |format|
      format.json do
        render json: hash_for_seat_change(seat_delta, seat_change, url)
      end

      format.html do
        GlobalInstrumenter.instrument(
          "render.seats_show",
          user_id: current_user.id,
          current_org_plan: current_organization.plan.name,
          current_seats_count: current_organization.seats,
          current_org_id: current_organization.id,
        )
        render "seats/show", locals: { target: target, seat_change: seat_change }
      end
    end
  end

  def remove_seats # rubocop:todo GitHub/UseRestfulActions
    url = remove_org_seats_path(target, seats: seat_delta, return_to: params[:return_to])

    respond_to do |format|
      format.json do
        render json: hash_for_seat_change(seat_delta, seat_change, url)
      end

      format.html do
        render "seats/remove_seats", locals: { target: target, seat_change: seat_change }
      end
    end
  end

  def cancel # rubocop:todo GitHub/UseRestfulActions
    unless satisfies_custom_role_requirements?
      flash[:error] = custom_role_error_message
      redirect_to target_billing_path(target) and return
    end

    if params[:survey_id].present? && params[:answers].present?
      SurveyAnswer.save_as_group(current_user.id, params[:survey_id], params[:answers])
    end

    result = GitHub::Billing.change_subscription(target, actor: current_user, plan: GitHub::Plan.free)

    if result.success?
      flash[:notice] = "You've successfully canceled your plan for this organization, sorry to see you go!"
    else
      flash[:error] = result.error_message
    end

    redirect_to target_billing_path(target)
  end

  def switch # rubocop:todo GitHub/UseRestfulActions
    new_plan_name = params[:new_plan].presence || params[:plan].presence

    seat_limit = target.seat_limit_for_upgrades
    if params[:seats].to_i > seat_limit
      flash[:error] = "You cannot upgrade to a plan with more than #{seat_limit} " + "license".pluralize(seat_limit) +
        ". Please contact us at https://github.com/enterprise/contact for pricing and purchasing information."
      redirect_to target_billing_path(target) and return
    end

    new_plan = GitHub::Plan.find(new_plan_name)
    unless satisfies_custom_role_requirements?(new_plan)
      flash[:error] = custom_role_error_message(new_plan)
      redirect_to target_billing_path(target) and return
    end

    if params[:survey_id].present? && params[:answers].present?
      SurveyAnswer.save_as_group(current_user.id, params[:survey_id], params[:answers])
    end

    old_plan = target.plan
    old_seats = target.seats

    per_seat_pricing_model = Billing::PlanChange::PerSeatPricingModel.new(
      target,
      seats: params[:seats],
      plan_duration: params[:plan_duration] || target.plan_duration,
      new_plan: new_plan_name,
    )

    # Switch to the new plan and seats
    success = per_seat_pricing_model.switch \
      actor: current_user,
      payment_details: payment_details,
      business_owned: !!params[:business_owned],
      organization_details: params[:organization],
      job_status_id: synchronous_payment_collection_job_status.id

    # Publish payment method change event
    payment_method_id = params.dig(:billing, :zuora_payment_method_id)
    is_new_payment_method = target.payment_method&.payment_token != payment_method_id
    if success && is_new_payment_method
      publish_payment_method_changed_for(
        actor: current_user,
        account: target,
        payment_method: T.must(target.payment_method),
      )
    end

    # Render the upgrading page if we are collecting payment synchronously for this change
    if should_show_synchronous_payment_collection_upgrading_page?
      return render "billing_upgrade/upgrading", locals: {
        job_status_id: synchronous_payment_collection_job_status.id,
        new_plan: new_plan,
        new_seats: target.seats,
        old_plan: old_plan,
        old_seats: old_seats,
        price: per_seat_pricing_model.final_price,
        seat_delta: nil,
        target: target
      }
    elsif success
      if per_seat_pricing_model.duration_change_only?
        flash[:notice] = "You have been successfully switched to #{target.pending_cycle_plan_duration}ly billing."
      else
        flash[:notice] = "Your plan was changed successfully."
        analytics_ec_purchase(target, per_seat_pricing_model.final_price, "Upgrade")
      end
    else
      flash[:error] = per_seat_pricing_model.error_messages.join
    end

    analytics_event(
      **organization_plan_change_ga_event_attributes(
        success,
        target,
        current_user,
        old_plan.name,
        new_plan_name || target.plan.name,
        old_seats,
        target.seats
      )
    )

    if params[:return_to].present?
      safe_redirect_to params[:return_to],
      fallback: target_billing_path(target)
    else
      redirect_to target_billing_path(target)
    end
  end

  def update
    old_seat_count = target.seats

    result = GitHub::Billing.change_seats(target, seats: seat_change.seats, seat_delta: seat_delta,
      actor: current_user, collect_payment_job_id: synchronous_payment_collection_job_status.id)

    if result.success?
      if target.save
        seat_change_ga_label = [:old_seats, :seats].map do |kind|
          seats_volume_bucket(seat_change.send(kind))
        end.uniq.join(" -> ")

        # Render the upgrading page if we are collecting payment synchronously for this change
        if should_show_synchronous_payment_collection_upgrading_page?
          return render "billing_upgrade/upgrading", locals: {
            job_status_id: synchronous_payment_collection_job_status.id,
            new_plan: nil,
            new_seats: seat_change.seats,
            old_plan: nil,
            old_seats: old_seat_count,
            price: nil,
            seat_delta: seat_delta,
            target: target
          }
        elsif seat_delta > 0
          flash[:notice] = "Your purchase of #{pluralize(seat_delta, "more license")} was successful. Thanks!"

          publish_billing_seat_count_change_for(
            actor: current_user,
            user: target,
            old_seat_count: old_seat_count,
            new_seat_count: seat_change.seats,
          )

          analytics_event(
            category: "Orgs",
            action: "upgrade seats",
            label: seat_change_ga_label,
          )
        else
          flash[:notice] = "You have successfully downgraded to #{pluralize(target.pending_cycle_seats, "license")}."

          analytics_event(
            category: "Orgs",
            action: "downgrade seats",
            label: seat_change_ga_label,
          )
        end

        if params[:return_to].present?
          safe_redirect_to params[:return_to]
        else
          redirect_to target_billing_path(target)
        end

        return
      else
        flash.now[:error] = target.errors.full_messages.join
      end
    else
      flash.now[:error] = result.error_message
    end

    render "seats/show", locals: { target: target, seat_change: seat_change }
  end

  def trade_screening_update # rubocop:todo GitHub/UseRestfulActions
    return link_trade_screening_record_to_org if params.key?(:link_billing_info_to_org)
    return unlink_trade_screening_record_from_org if params.key?(:unlink_billing_info_from_org)
    return update_trade_screening_record if params[:billing_info_submit_btn].present?

    switch
  end

  private

  def seat_delta
    if billing_params = params[:billing]
      billing_params.fetch(:seats, 0)
    else
      params[:seats] || default_seat_delta
    end.to_i
  end

  def use_available_pending_plan_change
    next_pending_plan_change = target.pending_cycle_change
    if next_pending_plan_change&.changing_plan?
      target.plan = next_pending_plan_change.plan
    end
  end

  memoize def seat_change
    Billing::PlanChange::SeatChange.new(target, seats: target.seats + seat_delta)
  end

  def default_seat_delta
    case action_name
    when "remove_seats"
      -1
    when "show"
      1
    end
  end

  def ensure_downgradable
    redirect_to target_billing_path(target) unless target.has_downgradable_seats?
  end

  def ensure_per_seat_plan
    redirect_to target_billing_path(target) unless target.plan.per_seat?
  end

  def ensure_not_enterprise_or_invoiced
    if target.business.present?
      redirect_to enterprise_licensing_path(target.business)
    elsif target.invoiced?
      redirect_to target_billing_path(target)
    end
  end

  def redirect_if_business_owned
    if target.business.present?
      redirect_to target_billing_path(target)
    end
  end

  def ensure_target
    render_404 if nilable_target.nil?
  end

  sig { returns(T.nilable(Organization)) }
  memoize def nilable_target
    org = current_organization_for_member_or_billing
    if org && org.billing_manageable_by?(current_user)
      org
    end
  end

  sig { override.returns(Organization) }
  memoize def target
    T.must(nilable_target)
  end

  sig { params(actor: User, account: ::Billing::Types::Account, payment_method: PaymentMethod).void }
  def publish_payment_method_changed_for(actor:, account:, payment_method:)
    GlobalInstrumenter.instrument(
      "billing.payment_method.addition",
      actor_id: actor.id,
      account_id: account.id,
      payment_method_id: payment_method.id,
    )
  end

  # Internal: billing changes from business_plus to any other plan require the organization
  # to not have any custom roles.
  sig { params(new_plan: T.nilable(GitHub::Plan)).returns(T::Boolean) }
  def satisfies_custom_role_requirements?(new_plan = nil)
    return true if target.plan != GitHub::Plan.business_plus && new_plan != GitHub::Plan.business_plus

    target.all_custom_roles.count == 0
  end

  # Internal: the error message to be rendered if custom role requirements are not met.
  sig { params(new_plan: GitHub::Plan).returns(String) }
  def custom_role_error_message(new_plan = GitHub::Plan.free)
    "The #{new_plan.titleized_display_name} plan does not support custom roles. Please delete all custom roles before downgrading billing plan."
  end
end
