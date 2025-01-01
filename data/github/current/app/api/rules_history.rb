# typed: true
# frozen_string_literal: true

class Api::RulesHistory < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::RepositoryRulesDependency
  include RuleEngine::RuleSettingsDependency

  get "/repositories/:repository_id/rulesets/:ruleset_id/history", operation_id: "repos/get-repo-ruleset-history" do
    repo = find_repo!
    deliver_error!(404) unless repo.rules_history_api?

    control_access :update_repository_rulesets,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ruleset = get_repo_ruleset(repo)
    versions_array = get_versions_array(ruleset)
    deliver(:ruleset_history_hash, versions_array)
  end

  get "/organizations/:organization_id/rulesets/:ruleset_id/history", operation_id: "orgs/get-org-ruleset-history" do
    org = find_org!
    deliver_error!(404) unless org.rules_history_api?

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ruleset = get_org_ruleset(org)
    versions_array = get_versions_array(ruleset)
    deliver(:ruleset_history_hash, versions_array)
  end

  get "/enterprises/:enterprise_id/rulesets/:ruleset_id/history", operation_id: "enterprise-admin/get-enterprise-ruleset-history" do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.rules_history_api?

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    ruleset = get_enterprise_ruleset(enterprise)
    versions_array = get_versions_array(ruleset)
    deliver(:ruleset_history_hash, versions_array)
  end

  get "/repositories/:repository_id/rulesets/:ruleset_id/history/:version_id", operation_id: "repos/get-repo-ruleset-version" do
    repo = find_repo!
    deliver_error!(404) unless repo.rules_history_api?

    control_access :update_repository_rulesets,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ruleset = get_repo_ruleset(repo)
    version = get_version(ruleset, params[:version_id])
    deliver(:ruleset_version_hash, version, request_source: repo)
  end

  get "/organizations/:organization_id/rulesets/:ruleset_id/history/:version_id", operation_id: "orgs/get-org-ruleset-version" do
    org = find_org!
    deliver_error!(404) unless org.rules_history_api?

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ruleset = get_org_ruleset(org)
    version = get_version(ruleset, params[:version_id])
    deliver(:ruleset_version_hash, version, request_source: org)
  end

  get "/enterprises/:enterprise_id/rulesets/:ruleset_id/history/:version_id", operation_id: "enterprise-admin/get-enterprise-ruleset-version" do
    enterprise = find_enterprise!
    deliver_error!(404) unless enterprise.rules_history_api?

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    ruleset = get_enterprise_ruleset(enterprise)
    version = get_version(ruleset, params[:version_id])
    deliver(:ruleset_version_hash, version, request_source: enterprise)
  end

  private

  def get_version(ruleset, version_id)
    record_or_404 ruleset.histories.find_by(id: params[:version_id])
  end

  def get_repo_ruleset(repo)
    ensure_plan_supports_rules!(repo)
    record_or_404 repo.rulesets.find_by(id: params[:ruleset_id])
  end

  def get_org_ruleset(org)
    ensure_plan_supports_rules!(org)
    record_or_404 org.rulesets.find_by(id: params[:ruleset_id])
  end

  def get_enterprise_ruleset(enterprise)
    ensure_plan_supports_org_and_enterprise_rules!(enterprise)
    record_or_404 enterprise.rulesets.find_by(id: params[:ruleset_id])
  end

  def get_versions_array(ruleset)
    page_size = params[:per_page] ? params[:per_page].to_i : DEFAULT_PER_PAGE
    page_size = [page_size, MAX_PER_PAGE].min
    page = params[:page].to_i

    versions = ruleset.histories.preload(:updated_by).limit(page_size + 1)
    if page.present? && page > 1
      versions = versions.offset((page - 1) * page_size)
    end

    versions_array = T.must(versions.to_a)
    has_more = versions_array.size > page_size
    versions_array.slice!(page_size..) if has_more

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)

    versions_array
  end
end
