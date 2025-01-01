# typed: strict
# frozen_string_literal: true

class Businesses::Copilot::StandaloneEnterpriseSeatManagementController < Businesses::BusinessController
  extend T::Sig

  include ApplicationHelper
  include ReactHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  javascript_bundle :copilot

  allow_verified_fetch only: [:search, :destroy, :create, :download_usage]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index, :search]

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :check_business_is_copilot_standalone
  before_action :business_not_downgraded_to_free_plan_required
  before_action :check_business_is_copilot_billable
  before_action :check_business_is_not_trial
  before_action :check_business_is_copilot_enabled
  before_action :parse_json_params, only: [:create, :search]

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-for-business"
  end

  sig { void }
  def search # rubocop:todo GitHub/UseRestfulActions
    teams_payload = Copilot::Payloads::Businesses::EnterpriseTeamSearch.new(
      business: this_business,
      params: params
    ).call

    render json: teams_payload, status: :ok
  end

  sig { void }
  def index
    render_react_app(
      payload: payload,
      title: "GitHub Copilot Standalone",
      layout: "layouts/copilot/standalone_seat_management",
      ssr: false
    )
  end

  sig { void }
  def create
    enterprise_teams = this_business.enterprise_teams.where(id: params[:enterprise_team_ids])
    result = copilot_business.assign(enterprise_teams.to_a, T.must(current_user))

    if result.error
      render json: { error: result.error }, status: :unprocessable_entity
    else
      render json: payload, status: :created
    end
  end

  sig { void }
  def destroy
    enterprise_teams = this_business.enterprise_teams.where(id: params[:enterprise_team_ids])
    result = copilot_business.unassign(enterprise_teams.to_a, T.must(current_user))

    if result.error
      render json: { error: result.error }, status: :unprocessable_entity
    else
      render json: payload, status: :ok
    end
  end

  sig { void }
  def download_usage # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment "copilot.seat_management.generate_standalone_business_csv"
    GitHub.logger.info("Generating Standalone CSV", "gh.business.id" => this_business.id, "gh.user.id" => current_user&.id)
    send_data copilot_business.to_csv, filename: "#{this_business.slug.parameterize}-seat-usage-#{Time.current.to_i}.csv"
  end

  private

  sig { returns(Copilot::Business) }
  def copilot_business # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @copilot_business ||= T.let(Copilot::Business.new(this_business), T.nilable(Copilot::Business))
  end

  sig { void }
  def check_business_is_copilot_standalone
    render_404 unless copilot_business.copilot_standalone?
  end

  sig { void }
  def check_business_is_copilot_billable
    redirect_to enterprise_licensing_path(this_business) unless copilot_business.copilot_billable?
  end

  sig { void }
  def check_business_is_not_trial
    render_404 if this_business.trial?
  end

  sig { void }
  def check_business_is_copilot_enabled
    redirect_to enterprise_licensing_path(this_business) if copilot_business.copilot_disabled?
  end

  sig { returns(Copilot::Types::StandaloneBusinessSeatManagementIndexPayload) }
  def payload
    Copilot::Payloads::Businesses::SeatManagement.new(business: this_business, params: params).call
  end
end
