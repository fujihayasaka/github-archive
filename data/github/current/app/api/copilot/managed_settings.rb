# typed: true
# frozen_string_literal: true

class Api::Copilot::ManagedSettings < Api::App
  include Copilot::ContentExclusion::ApiHelper

  SOURCE_REPO_NAME = T.let(".github-private".freeze, String)
  LEGACY_COPILOT_SETTINGS_FILE_PATH = T.let(".github/copilot/settings.json".freeze, String)
  COPILOT_SETTINGS_FILE_PATHS = T.let(
    [
      "copilot/managed-settings.json".freeze,
      LEGACY_COPILOT_SETTINGS_FILE_PATH,
    ].freeze,
    T::Array[String]
  )
  COPILOT_SETTINGS_OVERRIDES_FILE_PATH = T.let("copilot/managed-settings-overrides.json".freeze, String)
  ENTERPRISE_TEAM_OVERRIDES_FEATURE_FLAG = T.let(:copilot_managed_settings_enterprise_team_overrides, Symbol)
  CLIENT_CACHE_MAX_AGE = T.let(300, Integer) # 5 minutes

  get "/copilot_internal/managed_settings", operation_id: :internal do
    @route_owner = "@github/agent-control-plane"

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::Public::User.new(current_user)
    deliver_error! 403 unless copilot_user.has_copilot_access?

    customer_id = copilot_user.provider_customer_id
    deliver_error! 404 unless customer_id

    enterprise = Customer.find_by(id: customer_id)&.billable_owner
    deliver_error! 404 unless enterprise.is_a?(Business)
    deliver_error! 404 if enterprise.seats_plan_basic?

    source_repo_id = enterprise.subagent_definitions_source_repository_id
    deliver_error! 404 if source_repo_id.blank?

    source_repo = Repositories::Public.find_active(source_repo_id)
    deliver_error! 404 unless source_repo&.name == SOURCE_REPO_NAME && source_repo&.private?

    GitHub.logger.info(
      "Resolved managed settings source repository",
      "gh.business.id": enterprise.id,
      "configured_source_repo_id": source_repo_id,
      "gh.repo.id": source_repo.id,
      "gh.repo.name": source_repo.name_with_owner_for_api,
    )

    content = if FeatureFlag.vexi.enabled?(Copilot::Cache::ManagedSettingsClient::FEATURE_FLAG, enterprise, default: false)
      bypass_cache = FeatureFlag.vexi.enabled?(Copilot::Cache::ManagedSettingsClient::BYPASS_FEATURE_FLAG, enterprise, default: false)
      cached = Copilot::Cache::ManagedSettingsClient.new(enterprise: enterprise).fetch(force_refresh: bypass_cache) do
        get_copilot_settings_blob(enterprise, source_repo)&.data || Copilot::Cache::ManagedSettingsClient::NOT_FOUND_SENTINEL
      end

      cached == Copilot::Cache::ManagedSettingsClient::NOT_FOUND_SENTINEL ? nil : cached
    else
      get_copilot_settings_blob(enterprise, source_repo)&.data
    end
    deliver_error! 404 if content.nil?

    if FeatureFlag.vexi.enabled?(ENTERPRISE_TEAM_OVERRIDES_FEATURE_FLAG, enterprise, default: false)
      content = apply_enterprise_team_overrides(content: content, source_repo: source_repo, enterprise: enterprise)
    end

    set_caching_headers!({ max_age: CLIENT_CACHE_MAX_AGE, etag: etag_for(content) })

    deliver_raw(content, content_type: "application/json; charset=utf-8")
  end

  private

  # Stable, content-derived ETag. Same content -> same ETag whether the data
  # came from a fresh git read or from the cache.
  def etag_for(data)
    Digest::SHA256.hexdigest(data)
  end

  def apply_enterprise_team_overrides(content:, source_repo:, enterprise:)
    raw_overrides = get_copilot_settings_overrides_blob(source_repo)&.data
    return content if raw_overrides.nil?

    parsed_overrides = GitHub::JSON.parse(raw_overrides)
    return content unless parsed_overrides.is_a?(Hash)

    override_team_slugs = parsed_overrides["enterpriseTeamSlugs"].is_a?(Array) ? parsed_overrides["enterpriseTeamSlugs"].grep(String) : []
    return content if override_team_slugs.empty?

    recognized_slugs = validate_team_slugs(override_team_slugs, enterprise, source_repo)
    return content if recognized_slugs.empty?

    permission_overrides = parsed_overrides["permissions"]
    return content unless permission_overrides.is_a?(Hash)

    parsed_settings = GitHub::JSON.parse(content)
    return content unless parsed_settings.is_a?(Hash)

    return content unless user_belongs_to_override_team?(current_user, enterprise, recognized_slugs)

    current_permissions = parsed_settings["permissions"]
    parsed_settings["permissions"] = if current_permissions.is_a?(Hash)
      current_permissions.deep_merge(permission_overrides)
    else
      permission_overrides
    end

    GitHub::JSON.dump(parsed_settings)
  rescue JSON::ParserError => e
    GitHub.logger.warn(
      "Failed to parse managed settings overrides file",
      "gh.business.id": enterprise.id,
      "gh.repo.id": source_repo.id,
      "error.class": e.class.name,
      "error.message": e.message,
    )
    content
  end

  def user_belongs_to_override_team?(user, enterprise, slugs)
    user.async_teams(with_business_teams: true).sync
      .where(type: "BusinessTeam", business_id: enterprise.id, slug: slugs)
      .exists?
  end

  def validate_team_slugs(override_team_slugs, enterprise, source_repo)
    existing_slugs = BusinessTeam.where(business_id: enterprise.id, slug: override_team_slugs).pluck(:slug)
    unrecognized = override_team_slugs - existing_slugs
    if unrecognized.any?
      GitHub.logger.warn(
        "Managed settings overrides file references unrecognized enterprise team slugs",
        "gh.business.id": enterprise.id,
        "gh.repo.id": source_repo.id,
        "unrecognized_slugs": unrecognized.join(", "),
      )
    end
    existing_slugs
  end

  def get_copilot_settings_blob(enterprise, repo)
    copilot_settings_file_paths.each do |path|
      blob = get_blob(repo, path)
      return blob if blob
    end
    nil
  end

  def get_copilot_settings_overrides_blob(repo)
    get_blob(repo, COPILOT_SETTINGS_OVERRIDES_FILE_PATH)
  end

  def get_blob(repo, path)
    default_branch_name = repo.default_branch
    return if default_branch_name.blank?

    default_branch = repo.heads.find(default_branch_name)
    return if default_branch.nil?

    oid = default_branch.target_oid
    return unless GitRPC::Util.valid_full_oid?(oid)

    blob = repo.blob(oid, path)
    return if blob.nil?
    return unless GitRPC::Util.valid_full_oid?(blob.oid)

    blob
  rescue StandardError => e
    GitHub.logger.warn(
      "Failed to read managed settings file",
      "gh.repo.id": repo.id,
      "error.class": e.class.name,
      "error.message": e.message,
    )
    nil
  end

  def copilot_settings_file_paths
    COPILOT_SETTINGS_FILE_PATHS
  end
end
