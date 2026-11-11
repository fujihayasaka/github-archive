# typed: false
# frozen_string_literal: true

module Organization::InsightsOnboardingDependency
  extend ActiveSupport::Concern

  # this event is used by the Insights team only to track changes in org plans
  def insights_publish_plan_change

    current_plan_name = plan&.name
    previous_plan_name = plan_before_last_save&.name

    # Free plan creations are not tracked in Insights
    free_plan_created = plan_before_last_save.nil? && plan == GitHub::Plan.free
    plan_unchanged = current_plan_name == previous_plan_name
    return if free_plan_created || plan_unchanged

    if plan.free? || plan.free_with_addons?
      action = :DOWNGRADE
    else
      action = :UPGRADE
    end

    plan_change_message = {
      user: login,
      previous_plan: previous_plan_name,
      current_plan: current_plan_name,
      action: action,
      organization: Hydro::EntitySerializer.organization(self),
    }

    GitHub::Logger.log({
      fn: "Organization::InsightsOnboardingDependency#insights_publish_plan_change",
      request_id: GitHub.context[:request_id],
      org_login: login,
      org_id: id,
      previous_plan: previous_plan_name,
      current_plan: current_plan_name,
      action: action,
    })

    GitHub.hydro_publisher.publish(plan_change_message, schema: "github.v1.BillingPlanChange", topic: "cp1-iad.ingest.github.v1.BillingPlanChange")
  end

  def insights_publish_user_destroy
    return if plan == GitHub::Plan.free

    plan_before_user_destroy = plan&.name

    user_destroy_message = {
      user: login,
      previous_plan: plan_before_user_destroy,
      current_plan: "",
      action: :DOWNGRADE,
      organization: Hydro::EntitySerializer.organization(self),
    }

    GitHub::Logger.log({
      fn: "Organization::InsightsOnboardingDependency#insights_publish_user_destroy",
      request_id: GitHub.context[:request_id],
      org_login: login,
      org_id: id,
      previous_plan: plan_before_user_destroy,
      current_plan: "",
      action: :DOWNGRADE,
    })

    GitHub.hydro_publisher.publish(user_destroy_message, schema: "github.v1.BillingPlanChange", topic: "cp1-iad.ingest.github.v1.BillingPlanChange")
  end
end
