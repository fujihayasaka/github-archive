# typed: strict
# frozen_string_literal: true

class Businesses::SeatsController < Businesses::BusinessController
  include BillingSettingsHelper
  include VerifiedFetchDependency

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :eligible_for_self_serve_payment_required
  before_action :dotcom_required
  before_action :non_emu_required
  before_action only: [:update] do
    T.bind(self, Businesses::SeatsController)

    check_trade_compliance(target: this_business, sdn_redirect: true, redirect_url: settings_billing_tab_enterprise_url(tab: :payment_information))
  end

  allow_verified_fetch only: [:show, :update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
  only: [:show]

  sig { void }
  def show
    return render_404 unless request.xhr?
    old_seats = this_business.seats
    new_seats = params[:seats].to_i
    manage_seats = Business::ManageSeats.new(business: this_business, new_seats: new_seats)
    seat_change = manage_seats.seat_change

    render json: {
      total_seats: new_seats,
      old_seats: old_seats,
      valid_seats: manage_seats.valid_seats,
      current_price: seat_change.current_price.abs.format,
      payment_due: manage_seats.payment_due,
      payment_due_notice: manage_seats.payment_due_notice,
      payment_increase: manage_seats.payment_increase,
      payment_decrease: manage_seats.payment_decrease,
      sales_tax_notice: manage_seats.sales_tax_notice,
      seat_cost_label: manage_seats.seat_cost_label,
    }
  end

  sig { void }
  def update
    old_seats = this_business.seats
    new_seats = params[:seats].to_i

    seat_delta = new_seats - old_seats
    max_seat_delta = ::Billing::ChangeSubscription::MAX_SEAT_DELTA

    return handle_error("You cannot change the number of seats while your #{this_business.name} enterprise is overdue for payment.") if this_business.dunning?
    return handle_error("You can only add or remove up to #{max_seat_delta} seats at a time.") if seat_delta.abs > max_seat_delta

    return handle_error("Number of seats has to be larger than 0.") if new_seats <= 0

    # Trials have limited to avoid abuse. This limit may be bypassed manually via support.
    return handle_error("Number of seats is limited to a maximum of 50 during the trial period.") if this_business.trial? && new_seats > 50

    return handle_error("Number of seats has to be different than current seats.") if seat_delta == 0

    if this_business.trial?
      # Trial seat updates happen immediately. Zuora subscriptions are created after the trial ends.
      this_business.seats = new_seats
      result = this_business.update(seats: new_seats)

      if result
        this_business.track_seat_upgrade_change(current_user, old_seats: old_seats, new_seats: new_seats)
        if seat_delta > 0
          update_seats_analytics_event(
            "upgrade_seats_trial",
            old_seats,
            new_seats,
          )
          handle_success("Your purchase of #{seat_delta} #{"more seat".pluralize seat_delta} was successful, for a total of #{new_seats} #{"seat".pluralize new_seats}. Thanks!", new_seats)
        else
          update_seats_analytics_event(
            "downgrade_seats_trial",
            old_seats,
            new_seats,
          )
          handle_success("You have successfully downgraded to #{new_seats} #{"seat".pluralize new_seats}.", new_seats)
        end
      else
        handle_error("#{ this_business.errors.full_messages.join(", ") }")
      end
    elsif seat_delta > 0
      # When adding seats, add a plan change that immediately processes.
      result = Billing::SchedulePlanChange.run \
        account: this_business,
        actor: current_user,
        seats: new_seats,
        plan_duration: this_business.plan_duration,
        active_on: GitHub::Billing.today
      if result.success?
        update_seats_analytics_event(
          "upgrade_seats_paid",
          old_seats,
          new_seats,
        )
        handle_success("Your purchase of #{seat_delta} #{"more seat".pluralize seat_delta} was successful, for a total of #{new_seats} #{"seat".pluralize new_seats}. Thanks!", new_seats)
      else
        handle_error(result.error_message || "Sorry, we were unable to change your seats.")
      end
    else
      # Schedule downgrades for the next billing cycle.
      result = Billing::SchedulePlanChange.run \
        account: this_business,
        actor: current_user,
        seats: new_seats,
        plan_duration: this_business.plan_duration
      if result.success?
        update_seats_analytics_event(
          "downgrade_seats_scheduled",
          old_seats,
          new_seats,
        )
        handle_success("You have successfully downgraded to #{new_seats} #{"seat".pluralize new_seats}.", old_seats)
      else
        handle_error(result.error_message || "Sorry, we were unable to change your seats.")
      end
    end
  end

  private

  sig { params(error_message: String).void }
  def handle_error(error_message)
    respond_to do |format|
      format.html do
        flash[:business_seats_error] = error_message

        if params[:return_to].present?
          return safe_redirect_to params[:return_to], fallback: settings_billing_enterprise_path(this_business)
        else
          return redirect_to settings_billing_enterprise_path(this_business)
        end
      end
      format.json { render json: { error: error_message }, status: :unprocessable_entity }
    end
  end

  sig { params(success_message: String, current_seats: Integer).void }
  def handle_success(success_message, current_seats)
    respond_to do |format|
      format.html do
        flash[:business_seats_success] = success_message

        if params[:return_to].present?
          safe_redirect_to params[:return_to], fallback: settings_billing_enterprise_path(this_business)
        else
          redirect_to settings_billing_enterprise_path(this_business)
        end
      end

      # Return the updated payment amount and seat count to the client so that we can update the UI
      manage_seats = Business::ManageSeats.new(business: this_business, new_seats: current_seats)
      new_seat_count = manage_seats.valid_seats
      new_payment = manage_seats.seat_change.current_price.abs.format

      format.json { render json: { success: success_message, newPayment: new_payment, newSeatCount: new_seat_count, newPendingCycleChange: pending_cycle_seat_change_payload(this_business) } }
    end
  end

  sig { params(action: String, old_seats: Integer, new_seats: Integer).void }
  def update_seats_analytics_event(action, old_seats, new_seats)
    analytics_event(
      category: "business_self_serve_seats",
      action: action,
      label: "business_id:#{this_business.id},old_seats:#{old_seats},new_seats:#{new_seats}"
    )
  end
end
