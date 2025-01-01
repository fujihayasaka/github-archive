# typed: true
# frozen_string_literal: true

class Api::RepositoryRules < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::RepositoryRulesDependency
  TIME_PERIODS = %w[hour day week month].freeze
  RULE_STATUSES = %w[all pass fail bypass].freeze
  RULESET_TARGETS = %w[branch push tag repository].freeze

  get "/repositories/:repository_id/rulesets/rule-suites", operation_id: "repos/get-repo-rule-suites" do
    repo = find_repo!

    control_access :update_repository_rulesets,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_rules!(repo)

    filter_results = check_rule_suite_filters(params, repo)
    actor = filter_results[:actor]
    time_period = filter_results[:time_period]
    ruleset = filter_results[:ruleset]
    rule_status = filter_results[:rule_status]
    page_size = filter_results[:page_size]

    suites, has_more = repo.fetch_rule_suites(page_size:, page: params[:page].to_i,
      ref: params[:ref], actor: actor, time_period: time_period, ruleset: ruleset, rule_status: rule_status, evaluate_status: "all")

    ensure_rule_suite_exists!(suites)

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)

    deliver(:simple_rule_suite_hash, suites, request_source: repo)
  end

  get "/repositories/:repository_id/rulesets/rule-suites/:rule_suite_id", operation_id: "repos/get-repo-rule-suite" do
    repo = find_repo!

    control_access :update_repository_rulesets,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_rules!(repo)

    rule_suite_id = params[:rule_suite_id]

    suite = repo.fetch_rule_suite(rule_suite_id)
    ensure_rule_suite_exists!(suite)

    deliver(:rule_suite_hash, suite, request_source: repo)
  end

  get "/repositories/:repository_id/rulesets", operation_id: "repos/get-repo-rulesets" do
    repo = find_repo!
    # users with read access to a repo can see the rulesets
    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_rules!(repo)

    include_parents = params[:includes_parents].present? ? parse_bool(params[:includes_parents]) : true

    targets = params[:targets].split(",").collect(&:strip).uniq if params[:targets]
    if targets
      # validate the targets
      # We need to validate manually because we are using x-graceful-enum
      # we can remove this once member_privilege_rulesets ff is removed
      targets.all? { |t| RULESET_TARGETS.include?(t) } || deliver_error!(422, message: "Invalid target found")
    end
    rulesets = RepositoryRuleset.load_for(source: repo, include_parents: include_parents, targets: targets)
    rulesets = rulesets.filter { |r| r.enabled? || r.source == repo }

    paginated_rulesets = paginate_rel(rulesets)
    deliver(:simple_repository_ruleset_hash, paginated_rulesets, request_source: repo)
  end

  post "/repositories/:repository_id/rulesets", operation_id: "repos/create-repo-ruleset" do
    repo = find_repo!
    control_access :update_repository_rulesets,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_rules!(repo)
    ensure_repo_writable!(repo)

    data = receive_with_openapi

    if RepositoryRuleset.limit_reached?(repo)
      deliver_error!(422, errors: "The ruleset limit has been reached.")
    end

    ruleset = repo.rulesets.build

    update_repository_ruleset(ruleset, data, operation: "repos/create-repo-ruleset")

    deliver(:repository_ruleset_hash, ruleset, request_source: repo, status: 201)
  end

  get "/repositories/:repository_id/rulesets/:ruleset_id", operation_id: "repos/get-repo-ruleset" do
    repo = find_repo!

    # users with read access to a repo can see the rulesets
    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_rules!(repo)

    ruleset_id = params[:ruleset_id].to_i

    include_parents = params[:includes_parents].present? ? parse_bool(params[:includes_parents]) : true

    ruleset = if include_parents
      # allow lookup of rulesets from parent org
      rulesets = RepositoryRuleset.load_for(source: repo, include_parents: true)
      record_or_404 rulesets.find { |r| r.id == ruleset_id && (r.enabled? || r.source == repo) }
    else
      record_or_404 repo.rulesets.find_by(id: ruleset_id)
    end

    deliver(:repository_ruleset_hash, ruleset, request_source: repo)
  end

  put "/repositories/:repository_id/rulesets/:ruleset_id", operation_id: "repos/update-repo-ruleset" do
    repo = find_repo!

    control_access :update_repository_rulesets,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_rules!(repo)
    ensure_repo_writable!(repo)

    data = receive_with_openapi

    ruleset = record_or_404 repo.rulesets.find_by(id: params[:ruleset_id])

    ruleset = update_repository_ruleset(ruleset, data, operation: "repos/update-repo-ruleset")

    deliver(:repository_ruleset_hash, ruleset, request_source: repo)
  end

  delete "/repositories/:repository_id/rulesets/:ruleset_id", operation_id: "repos/delete-repo-ruleset" do
    repo = find_repo!

    control_access :update_repository_rulesets,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_rules!(repo)
    ensure_repo_writable!(repo)

    ruleset = record_or_404 repo.rulesets.find_by(id: params[:ruleset_id])

    if ruleset.destroy
      deliver_empty(status: 204)
    else
      deliver_error!(422, errors: ruleset.errors.full_messages)
    end
  end

  get "/repositories/:repository_id/rules/branches/*", operation_id: "repos/get-branch-rules" do
    repo = find_repo!

    # users with read access to a repo can see the rulesets
    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_rules!(repo)

    qualified_ref_name = "refs/heads/#{params[:splat].first}"

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: repo, ref_name: qualified_ref_name)
    rules = RepositoryRuleset.load_for(source: repo, include_parents: true).map do |ruleset|
      # should_evaluate? returns true for "evaluate" rulesets because insights still run for those. we explicitly
      # do not want "evaluate" rulesets returned for this endpoint, so check it separately.
      if ruleset.enabled? && ruleset.should_evaluate?(context)
        ruleset.rule_configurations
      end
    end.flatten.compact

    paginated_rules = paginate_rel(rules)
    deliver(:repository_rule_with_ruleset_source_hash, paginated_rules)
  end

  get "/organizations/:organization_id/rulesets", operation_id: "repos/get-org-rulesets" do
    org = find_org!

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(org)

    include_parents = params[:includes_parents].present? ? parse_bool(params[:includes_parents]) : true
    targets = params[:targets].split(",").collect(&:strip).uniq if params[:targets]
    if targets
      # validate the targets
      # We need to validate manually because we are using x-graceful-enum
      # we can remove this once member_privilege_rulesets ff is removed
      targets.all? { |t| RULESET_TARGETS.include?(t) } || deliver_error!(422, message: "Invalid target found")
    end
    rulesets = record_or_404 RepositoryRuleset.load_for(source: org, targets: targets, include_parents:)

    paginated_rulesets = paginate_rel(rulesets)
    deliver(:simple_repository_ruleset_hash, paginated_rulesets, request_source: org)
  end

  get "/organizations/:organization_id/rulesets/rule-suites", operation_id: "repos/get-org-rule-suites" do
    org = find_org!

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(org)

    filter_results = check_rule_suite_filters(params, org)
    actor = filter_results[:actor]
    time_period = filter_results[:time_period]
    ruleset = filter_results[:ruleset]
    rule_status = filter_results[:rule_status]
    page_size = filter_results[:page_size]

    # ensure repo is valid
    if params[:repository].present?
      repo = org.repositories.find_by(name: params[:repository])
    end

    suites, has_more = org.fetch_rule_suites(page_size:, page: params[:page].to_i,
      ref: params[:ref], actor: actor, time_period: time_period, ruleset: ruleset, rule_status: rule_status, repository: repo,  evaluate_status: "all")

    ensure_rule_suite_exists!(suites)

    build_pagination_link_headers(params[:page].to_i, page_size, has_more)
    deliver(:simple_rule_suite_hash, suites, request_source: org)
  end

  post "/organizations/:organization_id/rulesets", operation_id: "repos/create-org-ruleset" do
    org = find_org!

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(org)

    data = receive_with_openapi

    if RepositoryRuleset.limit_reached?(org)
      deliver_error!(422, errors: "The ruleset limit has been reached.")
    end

    ruleset = org.rulesets.build

    update_repository_ruleset(ruleset, data, operation: "repos/create-org-ruleset")

    deliver(:repository_ruleset_hash, ruleset, request_source: org, status: 201)
  end

  get "/organizations/:organization_id/rulesets/rule-suites/:rule_suite_id", operation_id: "repos/get-org-rule-suite" do
    org = find_org!

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(org)

    rule_suite_id = params[:rule_suite_id]

    suite = org.fetch_rule_suite(rule_suite_id)
    ensure_rule_suite_exists!(suite)

    deliver(:rule_suite_hash, suite, request_source: org)
  end

  get "/organizations/:organization_id/rulesets/:ruleset_id", operation_id: "repos/get-org-ruleset" do
    org = find_org!

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(org)

    ruleset = record_or_404 org.rulesets.find_by(id: params[:ruleset_id])

    deliver(:repository_ruleset_hash, ruleset, request_source: org)
  end

  put "/organizations/:organization_id/rulesets/:ruleset_id", operation_id: "repos/update-org-ruleset" do
    org = find_org!

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(org)

    data = receive_with_openapi

    ruleset = record_or_404 org.rulesets.find_by(id: params[:ruleset_id])

    ruleset = update_repository_ruleset(ruleset, data, operation: "repos/update-org-ruleset")

    deliver(:repository_ruleset_hash, ruleset, request_source: org)
  end

  delete "/organizations/:organization_id/rulesets/:ruleset_id", operation_id: "repos/delete-org-ruleset" do
    org = find_org!

    control_access :manage_organization_ref_rules,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(org)

    ruleset = record_or_404 org.rulesets.find_by(id: params[:ruleset_id])

    if ruleset.destroy
      deliver_empty(status: 204)
    else
      deliver_error!(422, errors: ruleset.errors.full_messages)
    end
  end

  post "/enterprises/:enterprise_id/rulesets", operation_id: "repos/create-enterprise-ruleset" do
    enterprise = find_enterprise!

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(enterprise)

    data = receive_with_openapi

    if RepositoryRuleset.limit_reached?(enterprise)
      deliver_error!(422, errors: "The ruleset limit has been reached.")
    end

    ruleset = enterprise.rulesets.build

    update_repository_ruleset(ruleset, data, operation: "repos/create-enterprise-ruleset")

    deliver(:repository_ruleset_hash, ruleset, request_source: enterprise, status: 201)
  end

  put "/enterprises/:enterprise_id/rulesets/:ruleset_id", operation_id: "repos/update-enterprise-ruleset" do
    enterprise = find_enterprise!

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(enterprise)

    data = receive_with_openapi

    ruleset = record_or_404 enterprise.rulesets.find_by(id: params[:ruleset_id])

    ruleset = update_repository_ruleset(ruleset, data, operation: "repos/update-enterprise-ruleset")

    deliver(:repository_ruleset_hash, ruleset, request_source: enterprise)
  end


  get "/enterprises/:enterprise_id/rulesets/:ruleset_id", operation_id: "repos/get-enterprise-ruleset" do
    enterprise = find_enterprise!

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(enterprise)

    ruleset = record_or_404 enterprise.rulesets.find_by(id: params[:ruleset_id])

    deliver(:repository_ruleset_hash, ruleset, request_source: enterprise)
  end

  get "/enterprises/:enterprise_id/rulesets", operation_id: "repos/get-enterprise-rulesets" do
    enterprise = find_enterprise!

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(enterprise)

    rulesets = record_or_404 RepositoryRuleset.load_for(source: enterprise)

    paginated_rulesets = paginate_rel(rulesets)
    deliver(:simple_repository_ruleset_hash, paginated_rulesets, request_source: enterprise)
  end

  delete "/enterprises/:enterprise_id/rulesets/:ruleset_id", operation_id: "repos/delete-enterprise-ruleset" do
    enterprise = find_enterprise!

    control_access :administer_business,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_org_and_enterprise_rules!(enterprise)

    ruleset = record_or_404 enterprise.rulesets.find_by(id: params[:ruleset_id])

    if ruleset.destroy
      deliver_empty(status: 204)
    else
      deliver_error!(422, errors: ruleset.errors.full_messages)
    end
  end

  private

  def check_rule_suite_filters(params, request_source)
    # ensure actor is valid if it exists
    if params[:actor_name].present?
      actor = User.find_by_login(params[:actor_name])
      ensure_rule_suite_filter_exists!(actor)
    end

    # ensure time period is valid
    time_period = TIME_PERIODS.include?(params[:time_period]) ? params[:time_period] : "day"

    if params[:ruleset_id].present?
      rulesets = RepositoryRuleset.load_for(source: request_source, include_parents: false)
      # ensure ruleset that is being filtered on is valid
      ruleset = rulesets.find { |ruleset| ruleset.id == params[:ruleset_id] }
      ensure_rule_suite_filter_exists!(ruleset)
    end

    # ensure result filter is valid
    rule_status = RULE_STATUSES.include?(params[:rule_suite_result]) ? params[:rule_suite_result] : "all"

    page_size = params[:per_page] ? params[:per_page].to_i : DEFAULT_PER_PAGE
    page_size = [page_size, MAX_PER_PAGE].min

    {
      actor: actor,
      time_period: time_period,
      ruleset: ruleset,
      rule_status: rule_status,
      page_size: page_size
    }
  end

  def ensure_plan_supports_rules!(repo)
    unless repo.plan_supports?(:protected_branches)
      deliver_error!(403, message: "Upgrade to GitHub Pro or make this repository public to enable this feature.")
    end
  end

  def ensure_plan_supports_org_and_enterprise_rules!(org)
    unless org.plan_supports?(:enterprise_rulesets)
      deliver_error!(403, message: "Upgrade to GitHub Enterprise to enable this feature.")
    end
  end

  def ensure_branch_exists!(ref)
    if ref.nil? || !ref.exists?
      deliver_error!(404, message: "Branch not found")
    end
  end

  def ensure_rule_suite_exists!(suite)
    if suite.nil?
      deliver_error!(404, message: "Rule suite not found")
    end
  end

  def ensure_rule_suite_filter_exists!(filter_option)
    if filter_option.nil?
      # Return empty result each if filter option is invalid
      deliver(:simple_rule_suite_hash, [])
    end
  end
end
