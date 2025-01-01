# typed: true
# frozen_string_literal: true

class Repos::CopilotSettings::ContentExclusionController < AbstractRepositoryController

  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :ensure_admin_access
  before_action :dotcom_required

  before_action :check_owner_is_organization
  before_action :check_if_billable
  before_action :feature_required
  before_action :parse_json_params, only: [:update]

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:show]

  def self.react_bundle_name
    "copilot-content-exclusion"
  end

  def show
    configs = Copilot::ContentExclusion.rules_for_repo(current_repository)

    org_level_rules = []
    ent_level_rules = []
    repo_config = T.let(nil, T.nilable(Copilot::ContentExclusionConfiguration))

    configs.each do |config, rules|
      next repo_config = config if config.resource_type == "Repository"

      paths = rules.collect(&:patterns).flatten.uniq.join("\n")
      name = config.resource.name

      case config.resource_type
      when "Organization"
        link = config.resource.adminable_by?(current_user) ? org_settings_copilot_content_exclusion_path(config.resource) : nil
        org_level_rules << { paths:, name:, link: }
      when "Business"
        link = config.resource.adminable_by?(current_user) ? settings_copilot_enterprise_path(config.resource, tab: "content-exclusion") : nil
        ent_level_rules << { paths:, name:, link: }
      end
    end

    render_react_app(
      payload: {
        organization: organization.display_login,
        repo: current_repository.name,
        lastEdited: repo_config&.updated_by ? { login: repo_config.updated_by&.display_login, time: repo_config.updated_at, link: audit_log_link } : nil,
        document: repo_config&.document,
        orgLevelRules: org_level_rules,
        entLevelRules: ent_level_rules
      },
      title: "Copilot content exclusion",
      page_data: {
        selected_link: :repo_settings_copilot_content_exclusion
      },
      layout: "layouts/repository/edit_repositories",
    )
  end

  def update
    content_exclusion_config = Copilot::ContentExclusionConfiguration.for_repository(current_repository).first
    new_paths = params[:paths]

    if content_exclusion_config.present?
      GitHub.logger.info("Updating ContentExclusionConfiguration", "gh.repo.id" => current_repository.id, "gh.copilot_ignore_config.id" => content_exclusion_config.id)
      content_exclusion_config.update(
        document: new_paths,
        updated_by: current_user,
      )
    else
      GitHub.logger.info("Creating ContentExclusionConfiguration", "gh.repo.id" => current_repository.id)
      content_exclusion_config = Copilot::ContentExclusionConfiguration.create(
        resource: current_repository,
        updated_by: current_user,
        resource_type: "Repository",
        document: new_paths
      )
    end

    if content_exclusion_config.valid?
      payload = {
        message: "Successfully updated the excluded paths",
        lastEdited: {
          login: current_user&.display_login,
          time: content_exclusion_config.updated_at,
          link: audit_log_link
        },
      }

      render json: payload
    else
      render json: { message: content_exclusion_config.errors.first.message }, status: :unprocessable_entity
    end
  end

  private

  sig { returns(::Organization) }
  def organization
    T.cast(owner, ::Organization)
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    Copilot::Organization.new(organization)
  end

  def check_owner_is_organization
    render_404 unless owner.organization?
  end

  def check_if_billable
    redirect_to settings_org_copilot_seat_management_path(organization) unless copilot_organization.copilot_billable? || copilot_organization.on_free_trial?
  end

  def feature_required
    render_404 unless Copilot::ContentExclusion.is_available?(current_repository)
  end

  def audit_log_link
    return nil unless current_repository.owner.adminable_by?(current_user)
    query = Search::Queries::AuditLogQuery.stringify(["repo:#{organization.display_login}/#{current_repository.name}", "action:#{Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED}"])
    settings_org_audit_log_path(organization, q: query)
  end
end
