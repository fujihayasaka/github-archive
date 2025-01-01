# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::SemanticCodeSearchController < Orgs::Controller
  extend T::Sig
  include ReactHelper
  include ApplicationHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_copilot_available
  before_action :check_feature_flags

  sig { returns(String) }
  def self.react_bundle_name
    "semantic-code-search-settings"
  end

  javascript_bundle :settings
  javascript_bundle :copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    indexed_repos = CopilotIndexedRepositories.select(:repository_id).where(organization_id: current_organization.id)
    indexed_repo_ids = indexed_repos.map { |repo| repo.repository_id }
    indexed_repos = Repositories::Public.load_repositories(indexed_repo_ids)
    # Make sure the repos are owned by the current org and are accessible by the current user
    indexed_repos = indexed_repos.select { |repo| repo.owner_display_login == current_organization.display_login && repo.readable_by?(current_user) }
    indexed_repos = indexed_repos.map { |repo| { name: repo.name, owner: repo.owner_display_login, description: repo.description, id: repo.id } }

    quota = CopilotIndexedRepositories::DEFAULT_COPILOT_INDEXING_QUOTA
    if GitHub.flipper[:copilot_expanded_indexing_quota].enabled?(current_user)
      quota *= 2
    end
    render_react_app(
      payload: {
        quota: quota,
        initialIndexedRepos: indexed_repos,
        orgName: current_organization.display_login,
        canIndexRepos: current_copilot_user&.dotcom_chat_enabled?,
      },
      title: "Semantic code search settings",
      layout: "layouts/settings/copilot_org_react",
      page_data: { send_vitals: true, selected_link: :organization_copilot_settings_semantic_code_search },
      ssr: true
    )
  end

  private

  sig { void }
  def check_feature_flags
    render_404 unless GitHub.flipper[:copilot_semantic_code_search_settings].enabled?(current_organization) && !GitHub.flipper[:bypass_copilot_indexing_limitations].enabled?(current_user)
  end

  sig { void }
  def check_copilot_available
    render_404 unless copilot_organization.has_copilot_for_business? || (copilot_organization.business_trial && T.must(copilot_organization.business_trial).has_trial?)
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  def check_emu
    redirect_to "/settings/profile" if current_copilot_user&.is_enterprise_managed?
  end
end
