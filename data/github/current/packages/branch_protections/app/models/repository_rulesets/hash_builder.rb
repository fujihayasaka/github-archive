# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  module HashBuilder
    extend T::Helpers
    extend T::Sig
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
        source_type: ruleset_source_type(ruleset),
        source: ruleset.source.name_with_display_owner,
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
            href: ruleset.url(source_view: request_source)
          },
        })
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
        source_type: ruleset_source_type(ruleset),
        source: ruleset.source.name_with_display_owner,
        enforcement: RepositoryRuleset::ENFORCEMENT_DISPLAY_VALUES[ruleset.enforcement].to_s,
        node_id: ruleset.global_relay_id,
        _links: {
          self: {
            href: api_url
          },
          html: {
            href: ruleset.url(source_view: options[:request_source])
          },
        },
        created_at: ruleset.created_at,
        updated_at: ruleset.updated_at
      }
      hash
    end

    def repository_rule_with_ruleset_source_hash(rule, options = {})
      payload = repository_rule_hash(rule, options)
      ruleset = rule.repository_ruleset
      payload.merge({
        ruleset_source_type: ruleset_source_type(ruleset),
        ruleset_source: ruleset.source.name_with_display_owner,
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

    sig { params(ruleset: RepositoryRuleset).returns(String) }
    def ruleset_source_type(ruleset)
      return "Organization" if ruleset.source_type == "User"
      return "Enterprise" if ruleset.source_type == "Business"
      ruleset.source_type
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
        pushed_at: suite.created_at.iso8601,
        result: suite_result_converter(suite.result),
      }

      if options[:evaluation_result].present?
        hash[:evaluation_result] = options[:evaluation_result]
      else
        eval_result = get_evaluation_result(suite)
        if !eval_result.empty?
          hash[:evaluation_result] = eval_result
        end
      end

      hash
    end

    def rule_suite_hash(suite, options = {})
      rule_runs = suite.rule_runs
      GitHub::PrefillAssociations.prefill_batch_method(rule_runs, :source_ruleset)

      # want to return an array of hashes
      rules_hashes = []
      evaluation_result = ""
      rule_runs.each do |rule_run|
        rules_hashes << rule_run_hash(rule_run)
        if suite.result == "allowed"
          if rule_run.result == "evaluate_failed" && evaluation_result != "fail"
            evaluation_result = "fail"
          elsif rule_run.result == "evaluate_allowed" && evaluation_result == ""
            evaluation_result = "pass"
          end
        end
      end

      hash = simple_rule_suite_hash(suite, { evaluation_result: })
      hash[:rule_evaluations] = rules_hashes

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
        rule_type: rule_run.rule_type
      }

      if rule_hash[:result] == "fail"
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

    def get_evaluation_result(suite)
      evaluation_result = ""
      if suite.result == "allowed"
        if suite.rule_runs.any? { |run| run.result == "evaluate_failed" }
          evaluation_result = "fail"
        elsif suite.rule_runs.all? { |run| run.result == "evaluate_allowed" }
          evaluation_result = "pass"
        end
      end

      evaluation_result
    end
  end
end
