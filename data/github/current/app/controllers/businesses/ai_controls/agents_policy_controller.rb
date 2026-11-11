# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::AgentsPolicyController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w[
    Businesses::AiControls::AgentsPolicyController#update_coding_agent_orgs_enablement
  ].freeze

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :handle_ai_controls_trial_entry_flow, only: [:index]
  before_action :ai_controls_read_required
  before_action :ai_controls_write_required, only: [:update_coding_agent_orgs_enablement, :search_orgs_by_custom_property]
  before_action :ensure_business_enterprise_management_policy, only: [:update_coding_agent_orgs_enablement, :search_orgs_by_custom_property]

  allow_verified_fetch only: [:search_orgs_by_custom_property]

  javascript_bundle :copilot, only: :index

  layout "layouts/react_business"

  javascript_bundle :copilot, only: :index

  sig { void }
  def index
    render "businesses/ai_controls/agents/index", locals: {
        business: this_business,
        copilot_business: copilot_business,
        can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
        is_admin: this_business&.adminable_by?(current_user) || false,
        render_copilot_swe_agent_settings: render_copilot_swe_agent_settings?,
        render_copilot_code_review_settings: render_copilot_code_review_settings?,
        render_copilot_code_review_beta_features_settings: render_copilot_code_review_beta_features_settings?,
        render_ccr_direct_org_billing_settings: render_ccr_direct_org_billing_settings?,
        render_cca_direct_org_billing_settings: render_cca_direct_org_billing_settings?,
    }
  end

  # The client sends only the diff: newly_enabled_organization_ids and
  # newly_disabled_organization_ids (integer IDs), so the server does not
  # need to resolve logins.
  sig { void }
  def update_coding_agent_orgs_enablement # rubocop:todo GitHub/UseRestfulActions
    enabled_ids = Array(params[:newly_enabled_organization_ids]).map(&:to_i)
    disabled_ids = Array(params[:newly_disabled_organization_ids]).map(&:to_i)

    redirect_path = agents_policy_enterprise_ai_controls_enterprise_path(this_business)
    changed_ids = (enabled_ids + disabled_ids).uniq
    if changed_ids.empty?
      return redirect_to redirect_path
    end

    # Verify orgs belong to this business and are copilot-enabled.
    copilot_enabled_ids = copilot_business.copilot_enabled_organization_ids_among(changed_ids)
    orgs_by_id = this_business.organizations.where(id: copilot_enabled_ids).includes(:business).index_by(&:id)

    orgs_to_enable = enabled_ids.filter_map { |id| orgs_by_id[id] && Copilot::Organization.new(orgs_by_id[id]) }
    orgs_to_disable = disabled_ids.filter_map { |id| orgs_by_id[id] && Copilot::Organization.new(orgs_by_id[id]) }

    Copilot::Policies::CodingAgent.bulk_update_orgs(orgs_to_enable, "enabled", force: true)
    Copilot::Policies::CodingAgent.bulk_update_orgs(orgs_to_disable, "disabled", force: true)

    redirect_to redirect_path
  end

  sig { void }
  def search_orgs_by_custom_property # rubocop:todo GitHub/UseRestfulActions
    property_name = params[:property_name].to_s
    value = params[:value].to_s

    if property_name.blank? || value.blank?
      return render json: { organizations: [] }
    end

    orgs = Orgs.domain.custom_properties.organizations_with_property_values(
      business: this_business,
      property_name: property_name,
      values: [value],
    ).to_a

    # Only include orgs that are copilot-enabled in this enterprise
    candidate_org_ids = orgs.map(&:id)
    copilot_enabled_org_ids = copilot_business.copilot_enabled_organization_ids_among(candidate_org_ids)
    copilot_enabled_org_id_set = copilot_enabled_org_ids.to_set
    matching_orgs = orgs.select { |org| copilot_enabled_org_id_set.include?(org.id) }

    coding_agent_state_by_org_id = Copilot::Policies::CodingAgent.coding_agent_state_by_org_id(
      org_ids: matching_orgs.map(&:id),
    )

    render json: {
      organizations: matching_orgs.map do |org|
        {
          id: org.id,
          login: org.display_login,
          avatar_url: org.primary_avatar_url(24),
          coding_agent_enabled: coding_agent_state_by_org_id[org.id] == "enabled",
        }
      end,
    }
  end

  private

  sig { void }
  def ai_controls_enabled?
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def ai_controls_write_required
    render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def ensure_business_enterprise_management_policy
    render_404 unless copilot_business.coding_agent_enterprise_management_enabled?
  end
end
