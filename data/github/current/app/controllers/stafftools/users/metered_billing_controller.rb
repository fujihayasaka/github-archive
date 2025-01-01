# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Stafftools::Users::MeteredBillingController < StafftoolsController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  include Stafftools::Users::ControllerLayoutMethods

  layout :billing_layout

  before_action :ensure_user_exists

  def actions # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/users/metered_billing/actions", locals: {
      repositories: aggregator.actions_usage_since_cycle_reset,
    }
  end

  def packages_bandwidth # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/users/metered_billing/packages_bandwidth", locals: {
      registry_packages: aggregator.packages_bandwidth_since_cycle_reset,
    }
  end

  def shared_storage_usage # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/users/metered_billing/shared_storage_usage", locals: {
      aggregated_usage_records: aggregator.shared_storage_usage,
    }
  end

  def actions_artifact_expirations # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/users/metered_billing/shared_storage", locals: {
      repositories: aggregator.upcoming_actions_artifact_storage_expirations,
    }
  end

  def copilot_usage # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/users/metered_billing/copilot_usage", locals: {
      aggregated_copilot_usage: aggregator.copilot_usage_since_cycle_reset,
      sum_of_copilot_usage: aggregator.copilot_usage_since_cycle_reset.sum { |usage| usage[:quantity] },
    }
  end

  def advance_quota_reset_date # rubocop:todo GitHub/UseRestfulActions
    if this_user.advance_metered_cycle_reset_date!
      flash[:notice] = "Successfully moved reset date to #{this_user.reload.next_metered_billing_cycle_starts_at.to_date}"
    else
      flash[:error] = "Failed to advance reset date"
    end

    redirect_to billing_stafftools_user_url(this_user)
  end

  def rebuild_from_events # rubocop:todo GitHub/UseRestfulActions
    repo_name = params[:repo_name]
    repo_id = Repository.find_by(owner_id: this_user.id, name: repo_name)&.id

    if repo_id.present?
      Billing::SharedStorage::RebuildAggregationFromEventsJob.perform_later(owner_id: this_user.id, repository_id: repo_id)
      flash[:notice] = "Rebuilding aggregation from events for #{this_user.login}/#{repo_name}..."
    else
      flash[:error] = "Failed to find repository #{this_user.login}/#{repo_name}"
    end

    redirect_back(fallback_location: billing_stafftools_user_url(this_user))
  end

  private

  def aggregator
    @_aggregator = ::Billing::Stafftools::MeteredUsageAggregation.new(owner_id: this_user.id)
  end
end
