# typed: true
# frozen_string_literal: true

class BillingUpgradeController < ApplicationController
  include OrganizationsHelper
  include MarketingMethods
  include SeatsHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories

  # This waits for a background job related to plan / seat upgrades to be completed. Once it begins,
  # a spinner is displayed to the user while it polls the given URL to see if the job has been completed or not.
  # Once the job is complete, the user is redirected.
  def index
    job_status = JobStatus.find(params[:job_status_id])
    return render_404 unless job_status
    return head 202 unless job_status.finished?

    # If the parameter new_plan_name is present, a plan upgrade was performed
    button_url, description, heading = if params[:new_plan_name]
      process_plan_upgrade(job_status: job_status).values_at(:button_url, :description, :heading)
    # If the parameter seat_delta is present, a seat upgrade was performed
    elsif params[:seat_delta]
      process_seat_upgrade(job_status: job_status).values_at(:button_url, :description, :heading)
    end

    render partial: "billing_upgrade/upgrade_complete", locals: {
      button_text: job_status.success? ? "View billing settings" : "Try again",
      button_url: button_url,
      description: description,
      heading: heading,
      target: target
    }
  end

  private

  def process_plan_upgrade(job_status:)
    price = Billing::Money.parse(params[:price])
    new_plan = GitHub::Plan.find(params[:new_plan_name])
    new_seats = params[:new_seats].to_i
    old_plan = GitHub::Plan.find(params[:old_plan_name])
    old_seats = params[:old_seats].to_i
    new_plan_display_name = new_plan.display_name.capitalize

    if job_status.success?
      flash[:notice] = "Your plan was changed successfully."
      flash[:analytics_location_params] = { target: target.class.name, billing: target.has_valid_payment_method?, plan: new_plan&.name, action: "upgrade" }

      heading = "Your #{display_target} has successfully been upgraded to GitHub #{new_plan_display_name}"
      description = ""
      button_url = billing_settings_url

      analytics_ec_purchase(target, price, "Upgrade")
    else
      heading = "Failed to upgrade your #{display_target} to GitHub #{new_plan_display_name}"
      description = format_error(job_status.error_message)
      button_url = upgrade_url(new_plan: new_plan.name)
    end

    if target.organization?
      analytics_event(
        **organization_plan_change_ga_event_attributes(
          job_status.success?,
          target,
          current_user,
          old_plan&.name,
          new_plan&.name,
          old_seats,
          new_seats,
        )
      )
    else
      analytics_event(
        category: "User",
        action: "plan upgrade",
        label: "#{old_plan&.display_name} -> #{new_plan&.display_name}"
      )
    end

    { button_url: button_url, description: description, heading: heading }
  end

  def process_seat_upgrade(job_status:)
    new_seats = params[:new_seats].to_i
    old_seats = params[:old_seats].to_i
    seat_delta = params[:seat_delta].to_i

    if job_status.success?
      flash[:notice] = "Your purchase of #{seat_delta} more #{"seat".pluralize(seat_delta)} was successful. Thanks!"

      heading = "You have successfully added #{seat_delta} new #{"seat".pluralize(seat_delta)} to your #{display_target}"
      description = ""
      button_url = billing_settings_url

      seat_change_ga_label = [old_seats, new_seats].map do |seat_count|
        seats_volume_bucket(seat_count)
      end.uniq.join(" -> ")

      publish_billing_seat_count_change_for(
        actor: current_user,
        user: target,
        old_seat_count: old_seats,
        new_seat_count: new_seats,
      )

      analytics_event(
        category: "Orgs",
        action: "upgrade seats",
        label: seat_change_ga_label,
      )
    else
      heading = "Failed to add #{seat_delta} new #{"seat".pluralize(seat_delta)} to your #{display_target}"
      description = format_error(job_status.error_message)
      button_url = org_seats_path(target, seats: seat_delta)
    end
    { button_url: button_url, description: description, heading: heading }
  end

  def ensure_target
    render_404 if params[:target] && target.nil?
  end

  def target_for_conditional_access
    # CAP is not needed if there is no target. We'd 404 in that case.
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  def billing_settings_url
    if target.organization?
      settings_org_billing_path(target)
    else
      settings_user_billing_path
    end
  end

  def format_error(message)
    if message&.match(/declined/i)
      "We were unable to process the payment. Please check your payment details or use another payment method"
    else
      "Something went wrong. Please try again later or contact support if the problem persists"
    end
  end

  def upgrade_url(new_plan: nil)
    if target.organization?
      upgrade_path(org: target, plan: new_plan, target: "organization")
    else
      upgrade_path(target: "user")
    end
  end

  def display_target
    if target.organization?
      "organization"
    else
      "account"
    end
  end

  memoize def new_plan
    GitHub::Plan.find(params[:new_plan])
  end

  memoize def target
    if params[:target] == "organization"
      org = current_organization_for_member_or_billing
      if org && org.billing_manageable_by?(current_user)
        org
      end
    else
      current_user
    end
  end
end
