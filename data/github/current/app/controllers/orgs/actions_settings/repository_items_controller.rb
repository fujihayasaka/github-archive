# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::RepositoryItemsController < Orgs::Controller
  include Actions::RunnerGroupsHelper
  include Actions::RunnersHelper
  include Orgs::RepositoryItemsHelper

  before_action :login_required
  before_action :ensure_permissions
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_can_use_org_runners
  before_action :ensure_page_specified

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index],
    optional: true

  RUNNER_GROUPS_POLICY = "RUNNER_GROUPS"
  ACCESS_POLICY = "ACCESS"
  REPO_SELF_HOSTED_RUNNERS = "REPO_SELF_HOSTED_RUNNERS"

  def index
    selected_repository_ids = []
    runner_group = nil
    form_id = nil

    if runner_group_policy?
      runner_group_id = policy_id.to_i
      runner_group = Actions::RunnerGroup.get(current_organization, id: runner_group_id, is_ui_read: true)
      return render_404 unless runner_group
      selected_repository_ids = runner_group.selected_targets.map(&:id).to_set
    elsif actions_access_policy?
      selected_repository_ids = current_organization.repositories.where(id: current_organization.actions_allowed_entities).map(&:global_id).to_set
    elsif repo_self_hosted_runners_policy?
      selected_repository_ids = current_organization.repositories.where(id: current_organization.repo_self_hosted_runners_allowed_entities).map(&:global_id).to_set
    end
    respond_to do |format|
      format.html do
        render(Organizations::Settings::RepositoryItemsComponent.new(
          organization: current_organization,
          repositories: additional_repositories(selected_repository_ids),
          selected_repositories: [],
          current_page: page,
          total_count: current_organization.repositories.size,
          data_url: data_url,
          aria_id_prefix: aria_id_prefix,
          repository_identifier_key: repository_identifier_key,
          form_id: form_id
        ), layout: false)
      end
    end
  end

  private

  def data_url
    settings_org_actions_repository_items_path(current_organization, page: page + 1, policy: policy, policy_id: policy_id)
  end

  def aria_id_prefix
    return policy unless policy_id.present?
    "#{policy}-#{policy_id}"
  end

  def policy
    params[:policy]
  end

  def policy_id
    params[:policy_id]
  end

  def rid_key
    case params[:rid_key]
    when :global_relay_id, "global_relay_id"
      :global_relay_id
    when :id, "id"
      :id
    else
      nil
    end
  end

  def source_repo_id
    params[:source_repo_id]
  end

  def repository_identifier_key
    return :global_relay_id unless rid_key.present?
    rid_key
  end

  def actions_bulk_selector_enabled?
    GitHub.enterprise? || FeatureFlag.vexi.enabled_or_raise?(:actions_bulk_selector, current_organization) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def ensure_permissions
    if runner_group_policy? || repo_self_hosted_runners_policy?
      ensure_user_has_runners_and_runner_groups_access
    elsif actions_access_policy?
      ensure_user_has_organization_actions_settings_access
    else
      organization_admin_required
    end
  end
end
