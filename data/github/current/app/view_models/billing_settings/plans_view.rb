# typed: true
# frozen_string_literal: true

module BillingSettings
  class PlansView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelpers
    include TextHelper
    include HydroHelper

    attr_reader :target, :actor, :request

    def initialize(target:, plan_name:, actor:, request:)
      @target = target
      @plan_name = plan_name
      @actor = actor
      @request = request
    end

    def selected_link
      "#{target || "user"}_billing_settings"
    end

    def plan_name
      @plan_name || target.plan.display_name
    end

    def new_cycle
      target.monthly_plan? ? "year" : "month"
    end

    def per_seat_plan_callout_url
      upgrade_path(
        plan: GitHub::Plan.business,
        target: "organization",
        org: target)
    end

    def per_seat_plan_callout_hydro_data(callout_location: nil, callout_text: nil)
      hydro_click_tracking_attributes("per_seat_plan_callout.click", {
        # N.B.: request_context is set in config/instrumentation/hydro.rb
        actor_id: actor.id,
        organization_id: target.id,
        callout_page: request.original_fullpath,
        callout_location: callout_location,
        callout_text: callout_text,
        callout_destination: per_seat_plan_callout_url,
        current_plan: target.plan.to_s,
      })
    end
  end
end
