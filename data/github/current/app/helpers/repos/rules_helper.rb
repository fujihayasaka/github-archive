# typed: strict
# frozen_string_literal: true

module Repos::RulesHelper
  extend T::Helpers
  include DocsUrlHelper

  requires_ancestor { ApplicationController }

  sig { params(source: RuleEngine::Types::RuleSource, user: T.nilable(User)).returns(T::Hash[Symbol, T.untyped]) }
  def rulesets_upsell_info(source, user)
    is_organization = source.is_a?(Organization) || (source.is_a?(Repository) && source.in_organization?)
    supports_rulesets = source.plan_supports?(:protected_branches)
    supports_evaluate_mode = (source.is_a?(Repository) && source.in_organization?) ||
     !source.is_a?(Repository)
    supports_enterprise_rulesets = source.plan_supports?(:enterprise_rulesets) && supports_evaluate_mode

    owner = if source.is_a?(Organization)
      source
    elsif source.is_a?(Repository)
      source.owner
    end

    adminable_by_user = if user.nil?
      false
    else
      source.adminable_by?(user)
    end

    org_member_repo_admin = if is_organization && source.is_a?(Repository)
      org = source.organization
      source.adminable_by?(user) && !T.must(org).adminable_by?(user)
    else
      false
    end

    rulesets_cta_path = if !adminable_by_user || source.is_a?(Business)
      nil
    elsif is_organization
      settings_org_plans_path(owner)
    else
      new_move_work_path(owner, repository: source, feature: MemberFeatureRequest::Feature::Rulesets.to_s)
    end

    enterprise_cta_path = if !adminable_by_user || source.is_a?(Business)
      nil
    elsif is_organization
      settings_org_plans_path(owner)
    else
      new_move_work_path(owner, repository: source, feature: "enterprise_rulesets")
    end

    # Organization rulesets are only supported for Enterprise
    if source.is_a?(Organization)
      if source.feature_flag_enabled?(:org_rulesets_for_team, default: false)
        supports_rulesets = supports_enterprise_rulesets || source.plan_supports?(:protected_branches, visibility: :private)
      else
        supports_rulesets = supports_enterprise_rulesets
      end
    end
    rulesets_cta_path = enterprise_cta_path if source.is_a?(Organization)

    {
      organization: is_organization,
      ask_admin: org_member_repo_admin,
      rulesets: {
        feature_enabled: supports_rulesets,
        cta: {
          visible: !supports_rulesets,
          path: rulesets_cta_path
        }
      },
      enterpriseRulesets: {
        feature_enabled: supports_enterprise_rulesets,
        cta: {
          visible: !supports_enterprise_rulesets,
          path: enterprise_cta_path
        }
      }
    }
  end

  sig { params(source: RuleEngine::Types::RuleSource).returns(T::Hash[Symbol, String]) }
  def rulesets_help_urls(source)
    supports_enterprise_rulesets = source.plan_supports?(:enterprise_rulesets)

    urls = {
      fnmatch: docs_url("repositories/rulesets-fnmatch-syntax"),
      statusChecks: docs_url("pull-requests/about-status-checks", ghec: supports_enterprise_rulesets),
      deploymentEnvironments: docs_url("actions/about-environments", ghec: supports_enterprise_rulesets),
      codeScanning: docs_url("code-security/enabling-code-scanning", ghec: supports_enterprise_rulesets),
      # Regex docs only available for enterprise
      commitMetadataRules: docs_url("repositories/rulesets-metadata-restrictions", ghec: true),
    }

    urls
  end

  sig do
    params(
      repo: Repository,
    ).returns(T::Array[String])
  end
  def push_ruleset_validation_errors(repo)
    errors = []
    errors << "Public repos cannot have push rules" if repo.public?
    errors << "Forked repos cannot have push rules" if repo.fork?
    errors << "Only org-owned repos can have push rules" unless repo.owner.is_a?(Organization)
    errors
  end

  sig do
    params(
      current_source: RuleEngine::Types::RuleSource,
      current_user: T.nilable(User),
      rulesets: T::Enumerable[RepositoryRuleset],
      read_only: T::Boolean,
      is_stafftools: T::Boolean,
      ref: T.nilable(Git::Ref),
      ref_list_cache_key: T.nilable(String),
    ).returns(T::Hash[String, T.untyped])
  end
  def ruleset_list_payload(current_source:, current_user:, rulesets:, read_only: false, is_stafftools: false, ref: nil, ref_list_cache_key: nil)
    source, source_type = source_payload_and_type(current_source)

    Repos::ReactPayload.camelize_keys({
      source:,
      source_type:,
      rulesets: rulesets.map do |ruleset|
        RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: current_source, include_bypass_actors: false, include_condition_metadata: false, actor: current_user)
      end,
      upsell_info: rulesets_upsell_info(current_source, current_user),
      branch: ref&.qualified_name,
      matching_rulesets: if ref
                           rulesets.filter { |ruleset| RulesEngine::RulesetMatcher.should_evaluate_ref?(ruleset, ref.repository, ref.qualified_name) }.map(&:id)
                         else
                           []
                         end,
      editable_rulesets: rulesets.filter do |ruleset|
        next false unless current_user
        ruleset.source.adminable_by?(current_user)
      end.map(&:id),
      branch_list_cache_key: ref_list_cache_key,
      read_only:,
      is_stafftools:,
    })
  end

  sig do
    params(
      current_source: RuleEngine::Types::RuleSource,
      current_user: T.nilable(User),
      ruleset: RepositoryRuleset,
      current_name: T.nilable(String),
      read_only: T::Boolean,
      include_bypass_actors: T::Boolean,
      is_stafftools: T::Boolean,
      is_imported_ruleset: T::Boolean,
      is_restored_ruleset: T::Boolean,
      is_history_view: T::Boolean,
      no_rulesets: T::Boolean,
      initial_errors: T.nilable(T::Hash[Symbol, T.untyped]),
    ).returns(T::Hash[String, T.untyped])
  end
  def ruleset_payload(current_source:, current_user:, ruleset:, current_name: nil, read_only: false, include_bypass_actors: true,
    is_stafftools: false, is_imported_ruleset: false, is_restored_ruleset: false, is_history_view: false, no_rulesets: false, initial_errors: nil)
    source, source_type = source_payload_and_type(current_source)

    payload = Repos::ReactPayload.camelize_keys({
      source:,
      source_type:,
      ruleset: RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: current_source, include_bypass_actors:, actor: current_user),
      current_name:,
      upsell_info: rulesets_upsell_info(current_source, current_user),
      rule_schemas: RulesEngine::ReactPayload.available_rule_schemas(ruleset),
      read_only:,
      base_avatar_url: GitHub.alambic_avatar_url,
      supported_condition_target_objects: current_source.supported_condition_target_objects(ruleset.target),
      help_urls: rulesets_help_urls(current_source),
      is_stafftools:,
      is_imported_ruleset:,
      is_restored_ruleset:,
      is_history_view:,
      no_rulesets:,
    })

    # avoid camelizing the initial errors to match PolicySettingsController#update error handling
    payload["initialErrors"] = initial_errors if initial_errors.present?

    payload
  end

  DEFAULT_PAGE = 1
  DEFAULT_PAGE_SIZE = 10
  MAX_PAGE_SIZE = 100

  sig do
    params(
      current_source: RuleEngine::Types::RuleSource,
      ruleset: RepositoryRuleset,
      read_only: T::Boolean,
      is_stafftools: T::Boolean,
      page_size: T.nilable(Integer),
      page: T.nilable(Integer),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def history_summary_payload(current_source:, ruleset:, read_only: false, is_stafftools: false, page_size: DEFAULT_PAGE_SIZE, page: DEFAULT_PAGE)
    source, source_type = source_payload_and_type(current_source)

    page ||= DEFAULT_PAGE
    page_size = page_size.present? ? [page_size, MAX_PAGE_SIZE].min : DEFAULT_PAGE_SIZE
    histories = ruleset.histories.preload(:updated_by).limit(page_size + 1)
    if page.present? && page > 1
      histories = histories.offset((page - 1) * page_size)
    end

    has_more_histories = histories.size > page_size

    histories_json = T.must(histories.to_a.slice(0, page_size)).map do |history|
      history.as_json(only: [
        :id,
        :created_at,
      ], include: [
        updated_by: {
          only: [
            :id,
            :display_login,
          ], methods: [
            :static_avatar_url,
          ], root: false
        }
      ], methods: [
        :is_current,
      ], root: false)
    end

    ruleset_json = {
      id: ruleset.id,
      name: ruleset.name,
      histories: histories_json,
    }

    Repos::ReactPayload.camelize_keys({
      source: source,
      source_type: source_type,
      ruleset: ruleset_json,
      page:,
      has_more: has_more_histories,
      read_only: read_only,
      is_stafftools: is_stafftools,
    })
  end


  # Returns the payload for comparing ruleset histories
  # @param source [RuleEngine::Types::RuleSource] the source of the ruleset
  # @param ruleset [RepositoryRuleset] the ruleset
  # @param history_id [Integer] the id of the history being viewed
  # @param compare_history_id [Integer] a previous history id to compare with the selected history
  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      ruleset: RepositoryRuleset,
      history_id: T.nilable(Integer),
      compare_history_id: T.nilable(Integer),
      current_user: T.nilable(User),
      is_stafftools: T::Boolean
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def history_comparison_payload(
    source:,
    ruleset:,
    history_id: nil,
    compare_history_id: nil,
    current_user: nil,
    is_stafftools: false
  )
    old_history, new_history = nil, nil
    if compare_history_id.present? && history_id.present?
      histories = ruleset.histories.where(id: [history_id, compare_history_id]).limit(2).group_by(&:id)
      new_history, old_history = histories[history_id.to_i]&.first, histories[compare_history_id.to_i]&.first
    elsif history_id.present?
      # If only a new id is present, just fetch the previous history
      # histories sorts in descending order, so the next history is the previous one
      histories = ruleset.histories.where("id <= ?", RepositoryRulesetHistory.find_by(id: history_id)).limit(2)
      # if there is no next previous, then this selected history is when the ruleset was created
      new_history, old_history = histories.first, (histories.second || RepositoryRulesetHistory.new(repository_ruleset: ruleset))
    else
      # TODO: return error if params are incorrect
      return
    end

    # TODO: return error if old or new history cannot be found
    return if new_history.nil? || old_history.nil?
    # TODO: return error when the fetched old history is newer than the fetched new history
    return if old_history.id && old_history.created_at > new_history.created_at

    old_blob, new_blob = [old_history, new_history].map do |history|
      RulesEngine::RulesetSerializer.history_to_html_string(history, user: current_user, is_stafftools:)
    end

    diff_html = GitHub::HTML::Diff.new(old_blob, new_blob).html
    Repos::ReactPayload.camelize_keys({
      ruleset: ruleset.as_json(only: [
        :id,
        :name,
      ], root: false),
      diff_html:,
      history: new_history.as_json(only: [
        :id,
        :created_at,
      ], root: false, include: [
        updated_by: {
          only: [
            :id,
            :display_login,
          ], methods: [
            :static_avatar_url,
          ], root: false
        }], methods: [
          :is_current,
        ]
      )
    })
  end

  PAGE_SIZE = 10
  TIME_PERIODS = T.let(%w[hour day week month].freeze, T::Array[String])
  RULE_STATUSES = T.let(%w[all pass fail bypass].freeze, T::Array[String])
  EVALUATE_STATUSES = T.let(%w[active all evaluate].freeze, T::Array[String])
  sig do
    params(
      viewing_source: RuleEngine::Types::RuleSource,
      filter: {
        actor: T.nilable(String),
        time_period: T.nilable(String),
        ruleset_name: T.nilable(String),
        rule_status: T.nilable(String),
        evaluate_status: T.nilable(String),
        ref: T.nilable(String),
        repository: T.nilable(String),
        organization: T.nilable(String),
      },
      page: Integer,
      ref_list_cache_key: T.nilable(String),
      read_only: T::Boolean,
    )
    .returns(T::Hash[Symbol, T.untyped])
  end
  def rule_insights_payload(viewing_source:, filter:, page:, ref_list_cache_key: nil, read_only: false)
    rulesets = RepositoryRuleset.load_for(source: viewing_source, include_parents: false)

    # ensure actor is valid if it exists
    actor = User.find_by_login(filter[:actor]) if filter[:actor].present?
    # ensure time period is valid
    time_period = TIME_PERIODS.include?(filter[:time_period]) ? filter[:time_period] : "day"
    # ensure ruleset is valid
    ruleset = rulesets.find { |ruleset| ruleset.name == filter[:ruleset_name] } if filter[:ruleset_name].present?
    # ensure repo is valid
    repo = (viewing_source.is_a?(Organization) ? viewing_source.repositories.find_by(name: params[:repository]) : nil) if params[:repository].present?
    # ensure org is valid
    org = (viewing_source.is_a?(Business) ? viewing_source.organizations.find_by(login: params[:organization]) : nil) if params[:organization].present?
    # ensure rule status is valid
    rule_status = RULE_STATUSES.include?(filter[:rule_status]) ? filter[:rule_status] : "all"
    # ensure evaluate status is valid
    evaluate_status = EVALUATE_STATUSES.include?(filter[:evaluate_status]) ? filter[:evaluate_status] : "active"

    # The ref is assumed to be a branch name
    ref = filter[:ref]&.present? ? "refs/heads/#{filter[:ref]}" : nil
    begin
      suites, has_more = viewing_source.fetch_rule_suites(page_size: PAGE_SIZE, page:, repository: repo, organization: org,
        ref:, actor:, time_period:, ruleset:, rule_status:, evaluate_status:)
      timed_out = false
    rescue RuleEngine::RuleSettingsDependency::RuleInsightsTimeoutError
      suites = []
      has_more = false
      timed_out = true
    end

    # Populate data for RuleSuites
    GitHub::PrefillAssociations.prefill_associations(suites, [:repository, :rule_runs, :event_action])
    GitHub::PrefillAssociations.prefill_batch_method(suites, :after_commit)

    ref_updates = suites.select { |s| s.event_action.is_a?(RuleEngine::EventActionRefUpdate) }.flat_map(&:event_action)
    GitHub::PrefillAssociations.prefill_batch_method(ref_updates, :after_commit)

    all_rule_runs = suites.flat_map(&:rule_runs)
    GitHub::PrefillAssociations.prefill_batch_method(all_rule_runs, :source_ruleset)
    GitHub::PrefillAssociations.prefill_batch_method(all_rule_runs.filter_map(&:source_ruleset), :latest_history_id)

    # Populate data for delegated-bypass related objects
    Promise.all([
      Promise.all(suites.map { _1.async_exemption_requests_used }),
      Promise.all(all_rule_runs.map { _1.async_exemption_responses }),
    ]).then do |requests, responses|
      # Prefill all actor info
      GitHub::PrefillAssociations.prefill_associations(requests.flatten, :requester)
      GitHub::PrefillAssociations.prefill_associations(responses.flatten, :reviewer)
    end.sync

    pr_summaries_by_id = create_pr_summaries(suites)

    source, source_type = source_payload_and_type(viewing_source)

    payload = {
      source:,
      source_type:,
      filter: {
        actor: RulesEngine::ReactPayload.actor_json(actor),
        time_period: time_period,
        ruleset: ruleset.present? ? RulesEngine::ReactPayload.simple_ruleset_json(ruleset) : nil,
        branch: filter[:ref],
        rule_status: filter[:rule_status],
        evaluate_status: filter[:evaluate_status],
        repository: filter[:repository],
        organization: filter[:organization],
        page: page,
      },
      upsell_info: !read_only ? rulesets_upsell_info(viewing_source, current_user) : nil,
      branch_list_cache_key: ref_list_cache_key,
      rulesets: rulesets.map { |ruleset| RulesEngine::ReactPayload.simple_ruleset_json(ruleset) },
      rule_suite_runs: suites.sort_by { |s| s.created_at }.reverse.filter_map do |suite|
        RulesEngine::ReactPayload.rule_suite_json(suite, pr_summaries_by_id, include_delegation: true) do |rule_run|
          rule_run.show_in_insights?(viewing_source, evaluate_status.to_sym)
        end
      end,
      visible_results: suites.to_h { |suite| [suite.id, suite.visible_result(viewing_source, evaluate_status.to_sym)] },
      has_more_suites: has_more,
      read_only:,
      timed_out:,
      learn_more_url: "#{GitHub.help_url}/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository#viewing-insights-for-rulesets",
    }

    if viewing_source.is_a?(Business)
      payload[:organizations] = viewing_source.organizations.pluck(:login)
    end

    Repos::ReactPayload.camelize_keys(payload) # rubocop:disable GitHub/AvoidCamelizeKeys
  end

  sig { params(rule_suite: RuleEngine::RuleSuite, resource_id: T::nilable(String)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def new_exemption_request_payload(rule_suite, resource_id: nil)
    suite_json = RulesEngine::ReactPayload.rule_suite_json(rule_suite, create_pr_summaries([rule_suite])) do |rule_run|
      rule_run.failed?
    end
    payload = {
      rule_suite: suite_json,
      has_post_approval_action: rule_suite.post_approval_action?,
    }
    if resource_id
      payload[:resource_id] = resource_id
    end
    Repos::ReactPayload.camelize_keys(payload)
  end

  sig do
    params(
      request: Exemptions::ExemptionRequest,
    ).returns(T::Array[T::Hash[T.untyped, T.untyped]])
  end
  def changed_push_rulesets(request)
    previous_suite = request.resource_owner
    rule_runs = previous_suite.rule_runs
    push_ruleset_rule_runs = rule_runs.filter { |run| run.rule_provider == "push_ruleset" }

    GitHub::PrefillAssociations.prefill_batch_method(push_ruleset_rule_runs, :source_ruleset)
    push_rulesets = push_ruleset_rule_runs.map do |run|
      {
        current_ruleset: run.source_ruleset,
        previous_history_id: run.rule_history_id
      }
    end.uniq
    current_rulesets = push_rulesets.map { |ruleset| ruleset[:current_ruleset] }
    GitHub::PrefillAssociations.prefill_batch_method(current_rulesets, :latest_history_id)

    changed_rulesets = []
    push_rulesets.each do |ruleset|
      break if ruleset[:current_ruleset].nil? || ruleset[:previous_history_id].nil?
      ruleset_changed = ruleset[:current_ruleset].latest_history_id != ruleset[:previous_history_id]
      if ruleset_changed
        changed_rulesets.push(ruleset[:current_ruleset].as_json(only: [:id, :name], root: false))
      end
    end

    changed_rulesets
  end

  sig do
    params(
      request: Exemptions::ExemptionRequest,
      is_invalid: T::Boolean,
    ).returns(T.any(Exemptions::ExemptionEvaluator::EvaluationResult, String))
  end
  def determine_request_status(request, is_invalid)
    case request.status
    when "cancelled", "completed"
      request.status
    else
      if request.expired?
        "expired"
      else
        if is_invalid
          "invalid"
        else
          request.compute_status
        end
      end
    end
  end

  sig do
    params(
      request: Exemptions::ExemptionRequest,
      viewer: T.nilable(User),
      limit_reviews: T::Boolean,
      responses: T.any(T.nilable(T::Array[Exemptions::ExemptionResponse]), ActiveRecord::Associations::CollectionProxy),
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def exemption_request_payload(request, viewer, limit_reviews: false, responses: nil)
    return nil if request.resource_owner.nil?

    if request.resource_owner.is_a?(RuleEngine::RuleSuite)
      rule_suite = T.let(request.resource_owner, RuleEngine::RuleSuite)
      suite_json = RulesEngine::ReactPayload.rule_suite_json(rule_suite, create_pr_summaries([rule_suite])) do |rule_run|
        rule_run.failed?
      end
      rulesets = RepositoryRuleset.where(id: suite_json[:rule_runs].map { |run| run[:ruleset_id] }) unless suite_json.nil?
      ruleset_names = rule_suite.rule_runs.map { |run| run.source_ruleset.nil? ? "deleted ruleset" : run.source_ruleset&.name }.uniq
      failed_rule_types = rule_suite.rule_runs.map(&:rule_type).compact.uniq
    else
      # request.resource_owner is a Repository
      repo = T.let(request.resource_owner, Repository)
      rulesets = []
      suite_json = {
        repository: {
          id: repo.id,
          owner_login: repo.owner&.display_login,
          name: repo.name,
          url: repo.permalink,
          name_with_owner: repo.name_with_display_owner,
          is_org_owned: T.must(request.repository).in_organization?,
        },
        created_at: request.created_at,
        actor: RulesEngine::ReactPayload.actor_json(request.requester),
      }
    end

    GitHub::PrefillAssociations.prefill_associations(responses, :reviewer) unless responses.nil?

    responses_json = responses&.map do |response| {
      reviewer: RulesEngine::ReactPayload.actor_json(response.reviewer),
      message: response.message,
      status: response.status,
      created_at: response.created_at,
      ruleset_ids: rulesets&.select { |ruleset| ruleset&.matches_bypassers?(response.reviewer, T.must(request.repository)) }&.map(&:id),
      id: response.id,
      updated_at: response.updated_at,
    }
    end || []
    reviewer = {
      # TODO: we should move this elsewhere or implement it differently (like different route, app payload, etc.)
      is_valid: request.is_valid_reviewer?(viewer),
      is_requester: request.requester == viewer,
      has_undismissed_review: limit_reviews ? request.has_undismissed_review_by_any_reviewer? : request.has_undismissed_review?(viewer),
      login: viewer.display_login
    } unless viewer.nil?

    rulesets = rulesets&.reject { |ruleset| ruleset.matches_bypassers?(T.must(request.requester), T.must(request.repository)) }
    if request.request_type == "push_ruleset_bypass"
      changed_push_rulesets = changed_push_rulesets(request)
    else
      changed_push_rulesets = []
    end
    is_invalid = changed_push_rulesets.length > 0

    payload = {
      rule_suite: suite_json,
      request: {
        requester: RulesEngine::ReactPayload.actor_json(request.requester),
        requester_comment: request.requester_comment,
        status: determine_request_status(request, is_invalid),
        created_at: request.created_at,
        updated_at: request.updated_at,
        metadata: request.metadata,
        resource_id: request.resource_identifier,
        changed_rulesets: changed_push_rulesets,
        expires_at: request.expires_at,
        ruleset_names:,
        failed_rule_types:,
        request_type: request.request_type,
      },
      rulesets: rulesets&.as_json(only: [:name, :id], methods: [:url], root: false),
      responses: responses_json,
      reviewer:,
      has_post_approval_action: request.post_approval_action?,
      post_approval_redirect_url: request.post_approval_redirect_url,
      enterprise: GitHub.enterprise?,
      actions_enabled: GitHub.actions_enabled?,
    }
    Repos::ReactPayload.camelize_keys(payload)
  end

  REQUEST_STATUSES = T.let(%w[completed cancelled expired denied approved open].freeze, T::Array[String])
  sig do
    params(
      viewing_source: RuleEngine::Types::RuleSource,
      filter: {
        approver: T.nilable(String),
        requester: T.nilable(String),
        time_period: T.nilable(String),
        request_status: T.nilable(String),
        repository: T.nilable(String),
        organization: T.nilable(String),
      },
      page: Integer,
      base_exemption_url: T.nilable(String),
      repo_exemptions_base_url_suffix: T.nilable(String),
      request_types: T::Array[String],
      required_repo_permission: T.nilable(Symbol),
    ).returns(T::Hash[String, T.untyped])
  end
  def rules_bypass_requests_payload(viewing_source:, filter:, page:, base_exemption_url:, repo_exemptions_base_url_suffix: nil, request_types: [], required_repo_permission: nil)
    code_scanning_request = request_types.include?(CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE)
    # ensure approver is valid if it exists
    approver = User.find_by_login(filter[:approver]) if filter[:approver].present?
    # ensure requester is valid if it exists
    requester = User.find_by_login(filter[:requester]) if filter[:requester].present?
    # ensure time period is valid
    default_time_period = "week"
    time_period = TIME_PERIODS.include?(filter[:time_period]) ? filter[:time_period] : default_time_period
    # ensure request status is valid
    request_status = REQUEST_STATUSES.include?(filter[:request_status]) ? filter[:request_status] : "all"
    # ensure repo is valid
    repo = viewing_source.is_a?(Organization) ? viewing_source.repositories.find_by(name: filter[:repository]) : nil if filter[:repository].present?
    # ensure org is valid
    org = (viewing_source.is_a?(Business) ? viewing_source.organizations.find_by(login: filter[:organization]) : nil) if filter[:organization].present?

    if code_scanning_request
      org = viewing_source if viewing_source.is_a?(Organization)
    end

    if required_repo_permission.nil? || viewing_source.is_a?(Repository)
      # required_repo_permission is only relevant for organization and business level queries. For repository queries,
      # fall back to querying all requests.
      exemption_requests, has_more = viewing_source.fetch_bypass_requests(repository: repo, organization: org, page_size: PAGE_SIZE, page: page,
        approver: approver, requester: requester, time_period: time_period, request_status: request_status, request_types:)
    else
      exemption_requests, has_more = Exemptions::BatchExemptionRequestQuery.new(viewing_source).fetch_exemption_requests_with_permissions_checking(
        current_user,
        required_repo_permission,
        repository: repo,
        organization: org,
        page: page > 0 ? page : 1,
        page_size: PAGE_SIZE,
        requester:,
        approver:,
        time_period:,
        request_status:,
        request_types:
      )
    end


    GitHub::PrefillAssociations.prefill_associations(exemption_requests, [
      { resource_owner: [:rule_runs] },
      :requester,
      :responses,
      :repository
    ])
    rule_runs = exemption_requests.flat_map { |request| request.resource_owner.respond_to?(:rule_runs) ? request.resource_owner.rule_runs : nil }
    GitHub::PrefillAssociations.prefill_batch_method(rule_runs, :source_ruleset)

    exemption_requests = exemption_requests.map do |request|
      resource_owner = request.resource_owner
      repository = request.repository
      ruleset_names = []
      failed_rule_types = []
      if resource_owner.is_a?(RuleEngine::RuleSuite)
        rule_runs = resource_owner.rule_runs.filter { |run| run.failed? }
        ruleset_names = rule_runs.map { |run| run.source_ruleset.nil? ? "deleted ruleset" : run.source_ruleset&.name }.uniq
        failed_rule_types = rule_runs.map(&:rule_type).compact.uniq
      end
      undismissed_responses = request.responses.filter { |response| response.status != "dismissed" }

      repo_exemptions_base_url = if repository.nil?
        nil
      else
        url_prefix = repo_exemptions_base_url_suffix ? repo_exemptions_base_url_suffix : "exemptions/"
        "/#{T.must(request.repository).name_with_display_owner}/#{url_prefix.gsub(/\/$/, "")}/"
      end

      {
        id: request.id,
        number: request.number,
        ruleset_names:,
        failed_rule_types:,
        requester: RulesEngine::ReactPayload.actor_json(request.requester),
        requester_comment: request.requester_comment,
        created_at: request.created_at,
        expires_at: request.expires_at,
        updated_at: request.updated_at,
        expired: request.expired?,
        status: request.status == "cancelled" || request.status == "completed" || request.status == "deleted" ? request.status : request.compute_status,
        metadata: request.metadata,
        request_type: request.request_type,
        resource_id: request.resource_identifier,
        repo_exemptions_base_url:,
        exemption_responses: undismissed_responses.map do |response|
          {
            id: response.id,
            exemption_request_id: response.exemption_request_id,
            reviewer: RulesEngine::ReactPayload.actor_json(response.reviewer),
            created_at: response.created_at,
            status: response.status,
            message: response.message
          }
        end,
        repo_name: request.repository&.name_with_display_owner,
        repo_url: request.repository&.permalink,
      }
    end


    if base_exemption_url.nil?
      base_exemption_url = "../../../exemptions/"
    end

    _, source_type = source_payload_and_type(viewing_source)

    payload = {
      exemption_requests: exemption_requests,
      filter: {
        approver: RulesEngine::ReactPayload.actor_json(approver),
        requester: RulesEngine::ReactPayload.actor_json(requester),
        time_period: time_period,
        page: page,
        request_status: filter[:request_status],
        repository: filter[:repository],
        organization: filter[:organization],
      },
      source_type:,
      has_more_requests: has_more,
      base_exemption_url: base_exemption_url
    }

    if !viewing_source.exemption_repos_query?
      if viewing_source.is_a?(Organization)
        payload[:repositories] = viewing_source.repositories.pluck(:name)
      end
    end

    if viewing_source.is_a?(Business)
      payload[:organizations] = viewing_source.organizations.pluck(:login)
    end

    Repos::ReactPayload.camelize_keys(payload) # Note that camelizing will recursively stringify all hash keys
  end

  sig { params(suites: T::Array[RuleEngine::RuleSuite]).returns(T::Hash[Integer, T.untyped]) }
  def create_pr_summaries(suites)
    # Gather all PR id's mentioned in metadata, so we can lookup their user-visible PR number, etc.
    pr_ids = suites.map do |suite|
      [
        suite.evaluation_metadata["pull_request"]&.[]("id"),
        suite.evaluation_metadata["merge_queue"]&.[]("group_pr_ids"),
      ]
    end
    .flatten.compact.uniq

    # Create a summary object for each mentioned PR
    PullRequest.find(pr_ids).each_with_object({}) do |pr, pr_hash|
      pr_hash[pr.id] = {
        id: pr.id,
        number: pr.number,
        link: pr.permalink,
      }
    end
  end

  sig do
    params(
      hash: T::Hash[Symbol, T.untyped]
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def sanitize_hash_for_export(hash)
    hash.delete(:created_at)
    hash.delete(:updated_at)
    hash.delete(:_links)
    hash.delete(:node_id)
    hash
  end

  sig do
    params(
      users: T::Array[User]
    ).returns(T::Hash[String, T.untyped])
  end
  def filter_suggestions(users)
    payload = {
      actors: users.compact.map { |user| RulesEngine::ReactPayload.actor_json(user) }
    }
    Repos::ReactPayload.camelize_keys(payload) # rubocop:disable GitHub/AvoidCamelizeKeys
  end

  sig { void }
  def ensure_user_has_edit_branch_protection
    render_404 unless current_repository.async_can_edit_repo_protections?(current_user).sync
  end

  sig { params(source: RuleEngine::Types::RuleSource).returns([T::Hash[Symbol, T.untyped], String]) }
  def source_payload_and_type(source)
    if source.is_a?(Repository)
      [Repos::ReactPayload.current_repository_payload(
        source,
        current_user_can_push: false # this is unsed in the ruleset UI
      ), "repository"]
    elsif source.is_a?(Business)
      [{
        id: source.id,
        name: source.name,
        ownerLogin: source.display_login,
        enterpriseManaged: source.enterprise_managed?,
      }, "enterprise"]
    else
      [{
        id: source.id,
        name: source.name,
        ownerLogin: source.display_login,
      }, "organization"]
    end
  end

  sig { params(source: RuleEngine::Types::RuleSource, imported_ruleset: T::Hash[String, T.untyped]).returns([T.nilable(RepositoryRuleset), T.nilable(String)]) }
  def validate_imported_ruleset(source, imported_ruleset)
    ruleset = nil

    begin
      ruleset = RepositoryRulesets::HashParser.to_repository_ruleset(
        source,
        imported_ruleset,
        validate_bypass_actors: source.rules_validate_bypass_actors_on_import?,
      )

    rescue RepositoryRuleset::InvalidTarget => e
      return [nil, e.message]
    rescue RepositoryRuleset::BypassActorsValidationError, RepositoryRulesetBypassActor::ValidationError => e
      return [nil, "The ruleset you are importing contains an invalid actor"]
    rescue RepositoryRuleset::Error => e
      return [nil, "Failed to import ruleset"]
    end
    [ruleset, nil]
  end
end
