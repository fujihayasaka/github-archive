# typed: strict
# frozen_string_literal: true

module RulesEngine
  module ReactPayload

    RuleFeatures = T.type_alias do
      {
        importExportEnabled: T::Boolean,
        historyEnabled: T::Boolean,
        supportedTargets: T::Array[String],
        listViewEnabled: T::Boolean,
      }
    end

    sig do
      params(source: RuleEngine::Types::RuleSource, user: T.nilable(User), supported_features: RuleFeatures, page_strings: T::Hash[Symbol, String], is_stafftools: T::Boolean).returns({
        enabled_features: T::Hash[Symbol, T::Boolean],
        page_strings: T::Hash[Symbol, String],
        is_stafftools: T::Boolean,
        supported_features: RuleFeatures,
        base_avatar_url: String,
      })
    end
    def self.app_payload(source, user, supported_features, page_strings, is_stafftools: false)
      {
        enabled_features: {
          a11y_add_bypass_dialog: source.a11y_add_bypass_dialog?,
          member_privilege_rulesets: source.member_privilege_rulesets_enabled?,
          rules_import_export_local_storage: source.rules_import_export_local_storage?,
          rules_selectpanel_cancel: source.rules_selectpanel_cancel?,
          org_rulesets_for_team: source.feature_flag_enabled?(:org_rulesets_for_team, default: false),
          rules_improved_panel_header: source.rules_improved_panel_header?,
          ruleset_configure_skip_actors: source.feature_enabled_for_source?(:ruleset_configure_skip_actors),
          custom_properties_for_orgs: source.is_a?(Business) && Orgs.domain.custom_properties.feature_enabled?(source)
        },
        supported_features:,
        page_strings:,
        is_stafftools:,
        base_avatar_url: GitHub.alambic_avatar_url,
      }
    end

    # A simple repository payload that has less data than the full payload.
    # Preload `owner` for best performance
    sig do
      params(repo: Repository).returns(T::Hash[Symbol, T.untyped])
    end
    def self.simple_repository_payload(repo)
      {
        id: repo.id,
        nodeId: repo.global_relay_id,
        name: repo.name,
        ownerLogin: repo.owner_display_login,
        public: repo.public?,
        private: repo.private?,
        isOrgOwned: repo.owner&.organization? || false,
      }
    end

    # A simple organization payload that has less data than the full payload.
    sig do
      params(org: Organization).returns(T::Hash[Symbol, T.untyped])
    end
    def self.simple_organization_payload(org)
      {
        id: org.id,
        nodeId: org.global_relay_id,
        name: org.display_login,
        primaryAvatarUrl: org.primary_avatar_url
      }
    end

    sig do
      params(
        ruleset: RepositoryRuleset,
        viewing_source: RuleEngine::Types::RuleSource,
        include_bypass_actors: T::Boolean,
        include_condition_metadata: T::Boolean,
        actor: T.nilable(User),
      )
      .returns(T::Hash[Symbol, T.untyped])
    end
    def self.ruleset_json(ruleset, viewing_source:, include_bypass_actors: true, include_condition_metadata: true, actor: nil)
      bypass_actors = ruleset.bypass_actors.filter_map do |bypass_actor|
        bypass_actor_as_json(bypass_actor, include_owner: true)
      end if include_bypass_actors

      {
        id: ruleset.id,
        target: ruleset.target,
        name: ruleset.name,
        source: {
          id: ruleset.source.id,
          type: ruleset.inherited_from_network ? "Upstream" : map_ruleset_source_type(ruleset.source_type),
          name: ruleset.source.name,
          url: ruleset.definition.edit_index_url,
        },
        enforcement: ruleset.enforcement,
        rules: ruleset.rule_configurations.filter_map do |rule|
          next unless ruleset.available_rule_types(allow_upsell: true).include?(rule.rule_type)

          rule_config_as_json(rule)
        end,
        conditions: ruleset.conditions.filter_map do |condition|
          next unless viewing_source.supported_condition_target_objects(ruleset.target).include?(condition.target_object)

          ruleset_condition_json(condition, load_metadata: include_condition_metadata)
        end,
        missing_condition_targets: ruleset.missing_condition_targets.map(&:serialize),
        bypass_actors:,
      }
    end

    sig { params(bypass_actor: RepositoryRulesetBypassActor, include_owner: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
    def self.bypass_actor_as_json(bypass_actor, include_owner: false)
      owner = bypass_actor.actor_owner_name if include_owner
      {
        id: bypass_actor.id,
        name: bypass_actor.actor_name,
        actorId: bypass_actor.actor_id,
        actorType: bypass_actor.actor_type,
        bypassMode: bypass_actor.bypass_mode,
        owner:,
        preferredAvatarUrl: bypass_actor.actor_preferred_avatar_url,
      }
    end

    sig { params(rule_config: RepositoryRuleConfiguration).returns(T::Hash[Symbol, T.untyped]) }
    def self.rule_config_as_json(rule_config)
      hash = {
        id: rule_config.id,
        rule_type: rule_config.rule_type,
        parameters: rule_config.parameters
      }

      metadata = rule_config.ruleset_ui_metadata
      if metadata
        hash[:metadata] = metadata
      end

      hash
    end

    sig { params(condition: RepositoryRuleCondition, load_metadata: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
    def self.ruleset_condition_json(condition, load_metadata: false)
      hash = {
        id: condition.id,
        target: condition.target,
        parameters: condition.parameters
      }
      if load_metadata
        metadata = condition.target_evaluator&.edit_ui_metadata(T.must(condition.repository_ruleset), condition.parameters)
        hash[:metadata] = metadata if metadata
      end

      hash
    end

    sig { params(ruleset: RepositoryRuleset).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.available_rule_schemas(ruleset)
      ruleset.available_rule_types(allow_upsell: true).map do |rule_type|
        rule = T.must(RuleEngine::Evaluator::REGISTERED_RULES[rule_type])
        {
          type: rule.rule_name,
          display_name: rule.display_name,
          description: rule.description,
          beta: rule.beta,
          parameter_schema: rule.parameter_schema_for_source(ruleset.source),
          metadata_pattern_schema: if rule.is_a?(RuleEngine::MetadataPatternRule)
                                     {
                                       property_description: rule.property_description,
                                       supported_operators: rule.supported_operators
                                     }
                                   else
                                     nil
                                   end,
        }
      end
    end

    sig { params(ruleset: RepositoryRuleset).returns(T::Hash[Symbol, T.untyped]) }
    def self.simple_ruleset_json(ruleset)
      {
        id: ruleset.id,
        name: ruleset.name,
        source: {
          id: ruleset.source.id,
          type: map_ruleset_source_type(ruleset.source_type),
          name: ruleset.source.name,
        },
        enforcement: ruleset.enforcement,
      }
    end

    sig do
      params(
        rule_suite: RuleEngine::RuleSuite,
        pr_summaries_by_id: T::Hash[Integer, T.untyped],
        include_delegation: T::Boolean, # Remove this arg when delegated-bypass FF is removed
        run_filter: T.nilable(T.proc
          .params(rule_run: RuleEngine::RuleRun)
          .returns(T::Boolean)
        ),
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def self.rule_suite_json(rule_suite, pr_summaries_by_id, include_delegation: false, &run_filter)
      return nil if rule_suite.result == "enter_queue_failed"

      rule_runs = run_filter.present? ? rule_suite.rule_runs.filter(&run_filter) : rule_suite.rule_runs

      if rule_suite.event_action
        event_action_type = rule_suite.event_action&.class&.to_s
        event_action_payload = rule_suite.event_action&.json_payload
      else
        # backward compatibility until event_actions are enabled and fully populated
        event_action_type = "RuleEngine::EventActionRefUpdate"
        event_action_payload =
        {
          repository_id: rule_suite.repository_id,
          ref_name: rule_suite.ref_name,
          before_oid: rule_suite.before_oid != GitHub::NULL_OID ? rule_suite.before_oid : nil,
          after_oid: rule_suite.after_oid != GitHub::NULL_OID ? rule_suite.after_oid : nil,
          policy_oid: rule_suite.policy_oid != GitHub::NULL_OID ? rule_suite.policy_oid : nil,
          commit: rule_suite.after_commit ? commit_json(T.must(rule_suite.after_commit)) : nil,
        }
      end

      payload = {
        id: rule_suite.id,
        rule_runs: rule_runs.filter_map { |rule_run| rule_run_json(rule_run, include_delegation) },
        repository: {
          id: rule_suite.repository&.id,
          owner_login: rule_suite.repository&.owner&.display_login,
          name: rule_suite.repository&.name,
          url: rule_suite.repository&.permalink,
          name_with_owner: rule_suite.repository&.name_with_display_owner,
          is_org_owned: rule_suite.repository&.in_organization?,
        },
        result: rule_suite.result,
        created_at: rule_suite.created_at,
        actor: actor_json(rule_suite.actor, use_ghost_for_nil: true),
        actor_is_public_key: rule_suite.actor.is_a?(PublicKey),
        evaluation_metadata: rule_suite_evaluation_metadata_json(rule_suite.evaluation_metadata, pr_summaries_by_id),
        used_exemption_requests: include_delegation ? rule_suite.exemption_requests_used.map { exemption_request_json(_1) } : nil,
        event_action_type: event_action_type,
      }.merge(event_action_payload)
      payload
    end

    sig do
      params(
        exemption_request: Exemptions::ExemptionRequest
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def self.exemption_request_json(exemption_request)
      return nil if exemption_request.nil?

      {
        id: exemption_request.id,
        number: exemption_request.number,
        status: exemption_request.status,
        requester: actor_json(exemption_request.requester),
        # TODO: Waiting for UI changes to routes.rb
        # url: UrlHelpers.ruleset_bypass_request_url(repo.owner, repo, exemption_request.number, host: GitHub.url),
        # FOR NOW: build the URL by hand :/
        url: exemption_request.repository ? "#{T.must(exemption_request.repository).permalink}/exemptions/#{exemption_request.number}" : nil,
      }
    end

    sig do
      params(
        rule_run: RuleEngine::RuleRun,
        include_delegation: T::Boolean, # Remove this arg when delegated-bypass FF is removed
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def self.rule_run_json(rule_run, include_delegation)
      {
        id: rule_run.id,
        ruleset_id: rule_run.repository_ruleset_id,
        rule_type: rule_run.rule_type,
        result: rule_run.result,
        rule_provider: rule_run.rule_provider,
        insights_category: rule_run.rule_insights_category,
        insights_source_out_of_date: rule_run.source_out_of_date?,
        message: rule_run.message,
        rule_display_name: RuleEngine::Evaluator.rule_impl_for_rule_type(rule_run.rule_type)&.display_name,
        metadata: rule_run.insights_ui_metadata,
        delegation_metadata: rule_run.delegation_metadata,
        exemption_responses: include_delegation ? rule_run.exemption_responses.map { exemption_response_json(_1) } : nil,
        violations: rule_run.violations,
      }
    end

    sig do
      params(
        exemption_response: Exemptions::ExemptionResponse
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def self.exemption_response_json(exemption_response)
      return nil if exemption_response.nil?

      request = exemption_response.exemption_request

      {
        id: exemption_response.id,
        exemption_request_id: exemption_response.exemption_request_id,
        # TODO: Waiting for UI changes to routes.rb
        # exemption_request_url: UrlHelpers.ruleset_bypass_request_url(repo.owner, repo, request.number, host: GitHub.url),
        # FOR NOW: build the URL by hand :/
        exemption_request_url: request&.repository ? "#{T.must(request.repository).permalink}/exemptions/#{request.number}" : nil,
        status: exemption_response.status,
        message: exemption_response.message,
        reviewer: actor_json(exemption_response.reviewer),
      }
    end

    sig { params(actor: T.untyped, use_ghost_for_nil: T::Boolean).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def self.actor_json(actor, use_ghost_for_nil: false)
      actor = public_key_user(actor) if actor.is_a?(PublicKey)
      actor = User.ghost if actor.nil? && use_ghost_for_nil

      return nil if actor.nil?
      {
        login: actor.display_login,
        name: actor.name,
        path: UrlHelper.actor_path(actor),
        primary_avatar_url: actor.primary_avatar_url(80)
      }
    end

    sig do
      params(
        evaluation_metadata: T::Hash[String, T.untyped],
        pr_summaries_by_id: T::Hash[Integer, T.untyped],
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def self.rule_suite_evaluation_metadata_json(evaluation_metadata, pr_summaries_by_id)
      result = {
        preReceiveFailure: evaluation_metadata["pre_receive_failure"],
        pullRequestHeadSha: evaluation_metadata["pull_request"]&.[]("head_sha"),
        pullRequestPolicySha: evaluation_metadata["pull_request"]&.[]("policy_sha"),
        pullRequestMergeBaseSha: evaluation_metadata["pull_request"]&.[]("merge_base_sha"),
        mergeQueueMergeMethod: evaluation_metadata["merge_queue"]&.[]("merge_method"),
        mergeQueueRemovalReason: evaluation_metadata["merge_queue"]&.[]("removal_reason"),
        blobEvaluation: evaluation_metadata["blob_evaluation"]
      }.compact

      if pr_id = evaluation_metadata["pull_request"]&.[]("id")
        result["pullRequest"] = pr_summaries_by_id[pr_id]
      end

      if merge_group_ids = evaluation_metadata["merge_queue"]&.[]("group_pr_ids")
        result["mergeGroupPullRequests"] = merge_group_ids.map { |id| pr_summaries_by_id[id] }
      end

      if check_results = evaluation_metadata["merge_queue"]&.[]("check_results")
        result["mergeQueueCheckResults"] = check_results.map do |chk|
          {
            context: chk["context"],
            state: chk["state"],
            integrationId: chk["integration_id"],
          }
        end
      end

      result
    end

    sig { params(public_key: T.untyped).returns(T.untyped) }
    private_class_method def self.public_key_user(public_key)
      return public_key.verifier if public_key.deploy_key?
      return public_key.user if public_key.user

      nil
    end

    sig { params(commit: Commit).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    private_class_method def self.commit_json(commit)
      return nil if commit.nil?

      {
        message: commit.message,
        short_message_html_link: (GitHub::Goomba::TitleMarkdownFilter.call(commit.short_message_html) unless commit.short_message_html.blank?),
      }
    end

    sig { params(source_type: String).returns(String) }
    private_class_method def self.map_ruleset_source_type(source_type)
      return "Enterprise" if source_type == "Business"
      return "Organization" if source_type == "User"
      source_type
    end
  end
end
