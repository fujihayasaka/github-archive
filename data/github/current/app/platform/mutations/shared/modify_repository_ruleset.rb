# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module ModifyRepositoryRuleset
        extend T::Helpers

        requires_ancestor { Kernel }

        def update_repository_ruleset(ruleset, inputs, context, operation: nil)
          RepositoryRuleConfiguration.transaction do
            if inputs[:name].present?
              ruleset.name = inputs[:name]
            end

            if inputs[:target].present?
              ruleset.target = inputs[:target]
            end

            if inputs[:enforcement].present?
              ruleset.enforcement = inputs[:enforcement]
            end

            if ruleset.source.member_privilege_rulesets_enabled? && ruleset.target == "repository"
              if ruleset.source.is_a?(Repository)
                raise Errors::Unprocessable.new("Repository rulesets cannot be created with repositories")
              end
              if ruleset.enforcement == "evaluate"
                raise Errors::Unprocessable.new("Repository rulesets cannot be set to evaluate")
              end
            end

            if inputs.include?(:bypass_actors)
              ruleset.upsert_bypass_actors(translate_bypass_actors(ruleset, inputs[:bypass_actors], context))
            end

            if inputs.include?(:conditions)
              conditions = inputs[:conditions]&.arguments&.keyword_arguments || {}
              transformed_conditions = conditions.filter_map do |target, condition|
                if condition
                  {
                    condition_type: condition[:type],
                    target: target,
                    parameters: params_for_condition(condition)
                  }
                end
              end

              ruleset.upsert_conditions(transformed_conditions)
            end

            if inputs.include?(:rules)
              rules = inputs[:rules] || []

              transformed_rules = rules.map do |rule|
                {
                  rule_type: rule[:type],
                  parameters: params_from_input(rule)
                }
              end

              ruleset.upsert_rules(transformed_rules, apply_default_parameters: true)
            end

            ruleset.save!
          end

          { ruleset: ruleset }
        rescue ActiveRecord::RecordInvalid
          raise Errors::Unprocessable.new(ruleset.errors.full_messages.join(", "))
        rescue RepositoryRuleset::ConditionValidationError => e
          raise Errors::Unprocessable.new(e.parse_error_messages.to_sentence)
        rescue RepositoryRuleset::RuleValidationError => e
          failed_rules = e.errors.map { |error| error.base.rule_type.humanize }
          raise Errors::Unprocessable.new("Invalid rules: \'#{failed_rules.uniq.join("\', \'")}\'")
        rescue ProtectedBranch::OnlyOrgsHaveAuthorizedActors
          raise Errors::Unprocessable.new("Only organization repositories can have users and team restrictions")
        rescue ProtectedBranch::TooManyPermittedActors => e
          raise Errors::Unprocessable.new(e.message)
        end

        def ensure_source_writable!(source, context:, operation:)
          if source.is_a?(::Repository)
            raise Errors::Forbidden.new("Upgrade to GitHub Pro or make this repository public to enable this feature.") unless source.plan_supports?(:protected_branches)
            raise Errors::Forbidden.new("Branch protection #{operation} is disabled on this repository.") unless source.can_update_protected_branches?(context[:viewer])

            raise Errors::Forbidden.new("Repository is archived") if source.archived?
            # For octoshift repo migrations only, we allow ruleset modification
            raise Errors::Forbidden.new("Repository is locked") if source.locked? && !(source.locked_on_migration? || source.is_importing?)
          elsif !source.is_a?(::Repository)
            raise Errors::Forbidden.new("Upgrade to GitHub Enterprise to enable this feature.") unless source.plan_supports?(:enterprise_rulesets)
          else
            raise Errors::Validation.new("Source is not a valid type")
          end
        end

        private

        def translate_bypass_actors(ruleset, bypass_actors, context)
          bypass_actors ||= []

          bypass_teams_apps = Promise.all(bypass_actors.filter_map do |actor|
            if actor[:actor_id]
              Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::Team, Objects::App], actor[:actor_id], context)
            end
          end).sync

          set_org_admin = T.let(false, T::Boolean)
          set_deploy_key = T.let(false, T::Boolean)
          filtered_bypass_actors = bypass_actors.filter_map do |actor|
            if actor[:bypass_mode] != 0 && ruleset.target != "branch"
              raise Errors::Unprocessable.new("bypass mode must be 'ALWAYS' for #{ruleset.target} rulesets")
            end
            if actor[:organization_admin]
              if actor[:bypass_mode] == 1
                ruleset.bypass_mode = :org_bypass_prs_only
              else
                ruleset.bypass_mode = :org_bypass_any
              end
              set_org_admin = true
              nil
            elsif actor.arguments.keyword_arguments.has_key?(:deploy_key)
              if actor[:deploy_key]
                if actor[:bypass_mode] != 0
                  # Deploy key does not support any other bypass mode
                  # We can't prohibit the input via the graphql inputs so raise an error instead
                  raise Errors::Unprocessable.new("deploy key bypass mode must be 'ALWAYS'")
                end
                ruleset.deploy_key_bypass = true
                set_deploy_key = true
              end
              nil
            elsif actor[:repository_role_database_id]
              owner = ruleset.source.is_a?(Repository) ? ruleset.source.owner : ruleset.source
              query = RepositoryRole.where(id: actor[:repository_role_database_id], owner_type: nil)
              role = if ruleset.source.fetch_roles_with_source_type?
                query.or(RepositoryRole.where(id: actor[:repository_role_database_id], owner_id: owner.id, owner_type: owner.type)).first
              else
                query.or(RepositoryRole.where(id: actor[:repository_role_database_id], owner: owner)).first
              end
              if role.nil?
                raise Errors::Unprocessable.new("An invalid Repository Role was specified as a bypass actor")
              end

              { actor_id: role.id, actor_type: "RepositoryRole", bypass_mode: actor[:bypass_mode] }
            elsif !actor[:enterprise_owner].nil?
              if actor[:enterprise_owner]
                { actor_id: 0, actor_type: "EnterpriseOwner", bypass_mode: actor[:bypass_mode] }
              else
                nil
              end
            else
              team_or_app = bypass_teams_apps.find { |team_app| team_app.global_relay_id == actor[:actor_id] }
              { actor_id: team_or_app.id, actor_type: team_or_app.class.name, bypass_mode: actor[:bypass_mode] }
            end
          end

          if !set_org_admin
            # org admin was not passed to bypass actors
            # so unset bypass actor
            ruleset.bypass_mode = :no_org_bypass
          end

          if !set_deploy_key
            # deploy key was not pass to bypass actors
            # unset bypass actor
            ruleset.deploy_key_bypass = false
          end

          filtered_bypass_actors
        end

        def params_from_input(rule)
          param_set = rule[:parameters]
          return nil if param_set.nil?

          if param_set.arguments.keys.size > 1
            raise Errors::Unprocessable.new("Only one rule parameter type can be specified.")
          end
          if param_set.arguments.keys.first.to_s != rule[:type]
            raise Errors::Unprocessable.new("The rule parameter type does not match the rule type of the rule.")
          end

          param_set.arguments[param_set.arguments.keys.first].to_h
        end

        def params_for_condition(condition)
          condition.arguments.keyword_arguments.filter { |key, _value| key != :type }.to_h
        end

      end
    end
  end
end
