# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  module HashBuilder
    extend T::Helpers
    include RuleEngine::Bypasses

    def repository_ruleset_hash(ruleset, options = {})
      request_source = options[:request_source]
      api_url = ruleset_api_url(ruleset, options, request_source: request_source)
      bypass_actors = ruleset.bypass_actors.map { |bypass_actor| bypass_actor_hash(bypass_actor, options) }
      if ruleset.org_bypass_any? || ruleset.org_bypass_prs_only?
        org_admin_role = {
          actor_id: RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS[:org_admin],
          actor_type: "OrganizationAdmin"
        }

        if ruleset.org_bypass_prs_only?
          org_admin_role[:bypass_mode] = "pull_request"
        else
          org_admin_role[:bypass_mode] = "always"
        end
        bypass_actors << org_admin_role
      end
      if ruleset.deploy_key_bypass
        bypass_actors << {
          actor_id: RepositoryRulesetBypassActor::DeployKey.id,
          actor_type: RepositoryRulesetBypassActor::DeployKey.type,
          bypass_mode: "always"
        }
      end

      hash = {
        id: ruleset.id,
        name: ruleset.name,
        target: ruleset.target,
        source_type: ruleset.display_source_type,
        source: ruleset.display_source_name,
        enforcement: RepositoryRuleset::ENFORCEMENT_DISPLAY_VALUES[ruleset.enforcement].to_s,
        conditions: repository_rule_conditions_hash(ruleset.conditions, options),
        rules: ruleset.rule_configurations.map { |rule| repository_rule_hash(rule, options) },
        node_id: ruleset.id ? ruleset.global_relay_id : nil,
        created_at: ruleset.created_at,
        updated_at: ruleset.updated_at
      }

      # There are no conditions on repository level push rulesets
      hash[:conditions] = nil if ruleset.target == "push" && ruleset.source_type == "Repository"

      if (hash[:source_type] == "Repository" &&
          ruleset.source.async_can_edit_repo_protections?(options[:current_user]).sync) ||
          (hash[:source_type] == "Organization" &&
          ruleset.source.can_manage_organization_ref_rules?(options[:current_user])) ||
          options[:staff_authorized] || # if user is a staff member and is authorized to view the resource
          options[:exporting_ruleset] # if user is exporting ruleset, which means they have permission
        hash[:bypass_actors] = bypass_actors
      end

      # this could be calculated for org or higher rulesets, but not in all cases. to save confusion, only
      # return this if the user called the repo-level endpoint, because it can always be calculated there.
      if request_source.is_a?(Repository) && options[:current_user]
        allowed_modes = allowed_ruleset_bypass_modes(ruleset, options[:current_user], request_source)

        if allowed_modes.include?(:any)
          hash[:current_user_can_bypass] = "always"
        elsif allowed_modes.include?(:pull_request)
          hash[:current_user_can_bypass] = "pull_requests_only"
        else
          hash[:current_user_can_bypass] = "never"
        end
      end

      if ruleset.id
        # Only add links if an id is present
        # otherwise there is nothing to link to
        hash = hash.merge(_links: {
          self: {
            href: api_url
          },
          html: {
            href: ruleset_html_url(ruleset, request_source, options[:current_user])
          },
        })
        hash[:_links].delete(:html) if hash[:_links][:html][:href].nil?
      end
      hash
    end

    def repository_rule_hash(rule, options = {})
      payload = {
        type: rule.rule_type
      }

      rule.visible_parameters.present? ? payload.merge(parameters: rule.visible_parameters) : payload
    end

    def simple_repository_ruleset_hash(ruleset, options = {})
      api_url = ruleset_api_url(ruleset, options, request_source: options[:request_source])
      hash = {
        id: ruleset.id,
        name: ruleset.name,
        target: ruleset.target,
        source_type: ruleset.display_source_type,
        source: ruleset.display_source_name,
        enforcement: RepositoryRuleset::ENFORCEMENT_DISPLAY_VALUES[ruleset.enforcement].to_s,
        node_id: ruleset.global_relay_id,
        _links: {
          self: {
            href: api_url
          },
          html: {
            href: ruleset_html_url(ruleset, options[:request_source], options[:current_user])
          },
        },
        created_at: ruleset.created_at,
        updated_at: ruleset.updated_at
      }
      hash[:_links].delete(:html) if hash[:_links][:html][:href].nil?
      hash
    end

    def repository_rule_with_ruleset_source_hash(rule, options = {})
      payload = repository_rule_hash(rule, options)
      ruleset = rule.repository_ruleset
      payload.merge({
        ruleset_source_type: ruleset.display_source_type,
        ruleset_source: ruleset.display_source_name,
        ruleset_id: ruleset.id
      })
    end

    def bypass_actor_hash(bypass_actor, options = {})
      {
        actor_id: bypass_actor.actor_id,
        actor_type: bypass_actor.actor_type,
        bypass_mode: api_ruleset_bypass_actor_bypass_mode(bypass_actor)
      }
    end

    def repository_rule_conditions_hash(conditions, options = {})
      conditions.map do |condition|
        repository_rule_condition_hash(condition, options)
      end.reduce({}, :merge)
    end

    def repository_rule_condition_hash(condition, options = {})
      request_source = T.let(options[:request_source], T.nilable(RuleEngine::Types::RuleSource))
      # If the condition doesn't support the source, we don't want to include it in the payload
      return {} unless request_source && RepositoryRuleCondition.supports_source?(condition, request_source)
      payload = {}
      payload[condition.target] = translate_ruleset_condition_parameters(condition, options)

      payload
    end

    def api_ruleset_bypass_actor_bypass_mode(bypass_actor)
      case
      when bypass_actor.bypass_mode == 1 # TODO: we can use the enum methods once the enum is enabled
        "pull_request"
      else
        "always"
      end
    end

    sig { params(ruleset: RepositoryRuleset, options: T.untyped, request_source: RuleEngine::Types::RuleSource).returns(String) }
    def ruleset_api_url(ruleset, options, request_source:)
      return "" if request_source.is_a?(Business) # TODO: enterprise ruleset API
      url_prefix = request_source.is_a?(Organization) ? "/orgs/#{request_source.login_for_api(use: options[:serialize_login])}" : "/repos/#{request_source.name_with_owner_for_api(use: options[:serialize_login])}"
      Api::Serializer.url("#{url_prefix}/rulesets/#{ruleset.id}")
    end

    sig { params(exemption_request: Exemptions::ExemptionRequest, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def delegated_bypass_hash(exemption_request, options = {})
      # strict loading of response.reviewer
      GitHub::PrefillAssociations.prefill_associations(exemption_request, [:responses])
      responses = exemption_request.responses.map do |response|
        {
          id: response.id,
          reviewer: {
            actor_id: response.reviewer&.id,
            actor_name: response.reviewer&.display_login,
          },
          status: response.status == "rejected" ? "denied" : response.status,
          created_at: response.created_at,
        }
      end

      data = exemption_request.exemption_data_hash
      changed_push_rulesets = changed_push_rulesets(exemption_request)
      is_invalid = changed_push_rulesets.length > 0
      repo = exemption_request.repository
      org = repo&.organization

      hash = {
        id: exemption_request.id,
        number: exemption_request.number,
        repository: simple_repo_hash(repo),
        organization: simple_org_hash(org),
        requester: actor_hash(exemption_request.requester),
        request_type: exemption_request.request_type,
        data: data ? data[:data] : nil,
        resource_identifier: exemption_request.resource_identifier,
        status: determine_request_status(exemption_request, is_invalid),
        requester_comment: exemption_request.requester_comment,
        expires_at: exemption_request.expires_at&.iso8601,
        created_at: exemption_request.created_at&.iso8601,
        responses: responses,
        url: "#{GitHub.api_url}/repos/#{repo&.name_with_display_owner}/bypass-requests/push-rules/#{exemption_request.number}",
        html_url: exemption_request.permalink,
      }

      hash
    end

    private

    def translate_ruleset_condition_parameters(condition, options = {})
      # Convert stored Node IDs to DB IDs
      if condition.target == "repository_id"
        params = condition.parameters.clone
        params["repository_ids"] = params["repository_ids"]&.map do |node_id|
          Platform::Helpers::NodeIdentification.from_global_id(node_id)[1].to_i
        end
        params
      elsif condition.target == "organization_id"
        params = condition.parameters.clone
        params["organization_ids"] = params["organization_ids"]&.map do |node_id|
          Platform::Helpers::NodeIdentification.from_global_id(node_id)[1].to_i
        end
        params
      elsif condition.target == "repository_property" && options[:request_source].is_a?(Organization)
        params = condition.parameters.clone

        %w[include exclude].each do |condition|
          params[condition].each { |property| property["source"] ||= "custom" }
        end

        params
      else
        condition.parameters
      end
    end

    def public_key_user(public_key)
      return public_key.verifier if public_key.deploy_key?
      return public_key.user if public_key.user

      nil
    end

    def actor_hash(actor)
      actor = public_key_user(actor) if actor.is_a?(PublicKey)

      return {} if actor.nil?
      {
        actor_id: actor.id,
        actor_name: actor.display_login
      }
    end

    sig { params(suite: RuleEngine::RuleSuite, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def simple_rule_suite_hash(suite, options = {})
      actor = actor_hash(suite.actor)
      hash = {
        id: suite.id,
        actor_id: actor[:actor_id],
        actor_name: actor[:actor_name],
        before_sha: suite.before_oid,
        after_sha: suite.after_oid,
        ref: suite.ref_name,
        repository_id: suite.repository_id,
        repository_name: suite.repository&.name,
        pushed_at: suite.created_at&.iso8601,
        result: suite_result_converter(suite.result),
      }

      # Only show the evaluate mode result if there are evaluate mode rules at this source level
      source_result = suite.source_results.find_by(source: options[:request_source])
      if source_result && !source_result.evaluate_result_none?
        hash[:evaluation_result] = suite_result_converter(suite.visible_result(options[:request_source], :all))
      end

      hash
    end

    sig { params(suite: RuleEngine::RuleSuite, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def rule_suite_hash(suite, options = {})
      rule_runs = suite.rule_runs
      GitHub::PrefillAssociations.prefill_batch_method(rule_runs, :source_ruleset)

      hash = simple_rule_suite_hash(suite, options)
      hash[:rule_evaluations] = rule_runs.filter_map do |rule_run|
        next unless rule_run.show_in_insights?(options[:request_source], :all)
        rule_run_hash(rule_run)
      end

      hash
    end

    sig { params(rule_run: RuleEngine::RuleRun, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def rule_run_hash(rule_run, options = {})
      if rule_run.ruleset_provider?
        type = "ruleset"
      else
        type = rule_run.rule_provider
      end

      rule_source = {
        type: type,
      }

      if type == "ruleset"
        ruleset = rule_run.source_ruleset

        if ruleset.present?
          rule_source[:id] = ruleset.id
          rule_source[:name] = ruleset.name
          enforcement = ruleset.enforcement == "enabled" ? "active" : ruleset.enforcement
        else
          # in case of deleted rulesets
          enforcement = "deleted ruleset"
        end
      else
        enforcement = "active"
      end

      rule_hash = {
        rule_source: rule_source,
        enforcement: enforcement,
        result: suite_result_converter(rule_run.result),
        rule_type: rule_run.rule_type,
      }

      if rule_run.failed? || rule_run.evaluate_failed?
        rule_hash[:details] = rule_run.message
      end

      rule_hash
    end

    def suite_result_converter(result)
      case result
      when "failed", "evaluate_failed"
        "fail"
      when "allowed", "evaluate_allowed"
        "pass"
      when "bypassed"
        "bypass"
      else
        result
      end
    end

    # Returns the URL for the ruleset in the UI
    # ruleset - the ruleset to link to
    # request_source - the source level of the request (was the request made at the repo, org, or enterprise level)
    # user - the user making the request
    sig do
      params(
        ruleset: RepositoryRuleset,
        request_source: T.nilable(RuleEngine::Types::RuleSource),
        user: T.nilable(RuleEngine::Types::Actor),
      ).returns(T.nilable(String))
    end
    def ruleset_html_url(ruleset, request_source, user)
      return if request_source.nil?

      # request source is repo and is a tag, push, or branch ruleset, return the readonly ui view (the only non-admin readonly view we have)
      if request_source.is_a?(Repository) && %w[tag push branch].include?(ruleset.target)
        return ruleset.url(source_view: request_source)
      end

      return unless user

      # if source is org and the user can modify the ruleset, return the edit url
      # OR if the source is an enterprise and the user can modify the ruleset, return the edit url
      if ((ruleset.source.is_a?(Organization) && ruleset.source.can_manage_organization_ref_rules?(user)) ||
        (ruleset.source.is_a?(Business) && ruleset.source.owner?(user))) && ruleset.id
        ruleset.definition.edit_url(T.must(ruleset.id))
      end
    end

    sig { params(repo: T.nilable(Repository)).returns(T::Hash[Symbol, T.untyped]) }
    def simple_repo_hash(repo)
      {
        id: repo&.id,
        name: repo&.name,
        full_name: repo&.name_with_display_owner,
      }
    end

    sig { params(org: T.nilable(Organization)).returns(T::Hash[Symbol, T.untyped]) }
    def simple_org_hash(org)
      {
        id: org&.id,
        name: org&.display_login,
      }
    end

    # This is a copy
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
        if request.expired? || is_invalid
          "expired"
        else
          status = request.compute_status.serialize
          status == "rejected" ? "denied" : status
        end
      end
    end

    # This is a copy
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
  end
end
