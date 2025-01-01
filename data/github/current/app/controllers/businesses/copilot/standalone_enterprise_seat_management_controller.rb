# typed: strict
# frozen_string_literal: true

class Businesses::Copilot::StandaloneEnterpriseSeatManagementController < Businesses::BusinessController

  include ApplicationHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Site::MicrosoftAnalyticsDependency

  javascript_bundle :copilot

  allow_verified_fetch only: [:search, :destroy, :create, :download_usage, :download_activity]

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
  before_action :enable_microsoft_analytics, only: [:index]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:index]

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
    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: Copilot::Payloads::Businesses::SeatManagement.new(business: this_business, params: params),
        title: "GitHub Copilot Standalone",
        layout: "layouts/copilot/standalone_seat_management",
        page_data: { selected_link: selected_link, sidebar: sidebar }
      )
    else
      render_react_app(
        payload: payload,
        title: "GitHub Copilot Standalone",
        page_data: { selected_link: selected_link, sidebar: sidebar },
        layout: "layouts/copilot/standalone_seat_management",
        disable_ssr: true
      )
    end
  end

  sig { void }
  def create
    enterprise_teams = this_business.enterprise_teams.where(id: params[:enterprise_team_ids])
    result = copilot_business.assign(enterprise_teams.to_a, current_user)

    if result.error
      render json: { error: result.error }, status: :unprocessable_entity
    else
      render json: payload, status: :created
    end
  end

  sig { void }
  def destroy
    enterprise_teams = this_business.enterprise_teams.where(id: params[:enterprise_team_ids])
    result = copilot_business.unassign(enterprise_teams.to_a, current_user)

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

  sig { void }
  def download_activity # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment "copilot.seat_management.generate_standalone_business_activity_csv"
    GitHub.logger.info("Generating Standalone Activity CSV", "gh.business.id" => this_business.id, "gh.user.id" => current_user&.id)

    Copilot::ActivityReportJob.perform_later(
      entity_id: this_business.id,
      entity_type: "business",
      actor_id: current_user.id,
    )

    render json: { ok: true }, status: 202 and return
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

  sig { returns(T::Boolean) }
  memoize def billed_via_billing_platform?
    this_business&.customer&.billed_via_billing_platform? || false
  end

  sig { returns(Symbol) }
  memoize def selected_link
    billed_via_billing_platform? ? :business_licensing : :enterprise_licensing
  end

  sig { returns(Symbol) }
  memoize def sidebar
    billed_via_billing_platform? ? :billing_and_licensing : :settings
  end
end
