# typed: true
# frozen_string_literal: true

# This controller is used to defer the loading of secret scanning bypass request counts.
# We're using the batch deferred interface to allow for async page load, even though we only
# call this endpoint once for the current organization.

# For more info on the batch deferred interface, see https://github.com/github/engineering/discussions/1613.

class Orgs::OrganizationSecretScanningBypassRequestsCountsController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Repositories,
  ApplicationRecord::Mysql5,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql2,
  ApplicationRecord::Collab,
  ApplicationRecord::Copilot,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Billing,
  ApplicationRecord::Configurations,
  ApplicationRecord::Spokes,
  only: [:index]

  depends_on_clusters  ApplicationRecord::SecurityOverviewAnalytics,
  ApplicationRecord::Notify,
  optional: true,
  only: [:index]

  before_action :organization_read_required
  before_action :check_bypass_request_list_access

  sig { void }
  def index
    count = current_organization.token_scanning_bypass_request_count
    response = {
      # Because we currently only call this endpoint once for the current org, we're hardcoding the expected format.
      "item-0": render_to_string(Primer::Beta::Counter.new(count: count, limit: 5_000, hide_if_zero: true))
    }
    respond_to do |format|
      format.json do
        render json: response
      end
    end
  end

  private

  def check_bypass_request_list_access
    return render_404 if current_user.nil?

    render_404 unless SecretScanning::Features::Org::DelegatedBypass.new(current_organization).can_view_requests_list?(current_user)
  end
end
