# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To run this locally: bin/safe-ruby lib/github/transitions/20231026171626_migrate_required_workflows_to_rulesets.rb --verbose --write

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MigrateRequiredWorkflowsToRulesets < Base
      # Duplicate of ActionsPolicy::RequiredWorkflow model to avoid creating unnecessary dependency
      class RequiredWorkflow < ApplicationRecord::Collab
        self.table_name = "required_workflows"

        enum :state, { active: 0, deleted: 1, invalid: 2 }, prefix: true
        enum :scope, { all: 0, selected: 1 }, prefix: true

        STATE_ACTIVE = "active"
        STATE_DELETED = "deleted"
        STATE_INVALID = "invalid"
        SCOPE_ALL = "all"
        SCOPE_SELECTED = "selected"
      end

      # Duplicate of ActionsPolicy::RequiredWorkflowRepository model to avoid creating unneeded dependency
      class RequiredWorkflowRepository < ApplicationRecord::Collab
        self.table_name = "required_workflow_repositories"
      end

      iterate_over :database_table, params: {
        model_class: RequiredWorkflow,
        columns: [:id, :owner_id, :name, :path, :repository_id, :scope, :ref, :state, :locked],
        conditions: "state != 1"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log_or_puts("Required workflows transition batch: is dry run: #{dry_run?}, first required workflow id: #{items.keys.first}, last required workflow id: #{items.keys.last}")
        successful_items = []
        unsuccessful_items = []
        valid_ruleset_ids = []

        # load all the imposee ("target") repos up front
        required_workflow_target_repos = {}
        target_repos = RequiredWorkflowRepository.where(required_workflow_id: items.keys).to_a
        target_repos.each do |repo|
          required_workflow_target_repos[repo.required_workflow_id] ||= []
          required_workflow_target_repos[repo.required_workflow_id] << repo.imposee_repository_id
        end
        repos = Repository.where(id: target_repos.map(&:imposee_repository_id).uniq).index_by(&:id)

        # load the orgs (and their configs) up front
        orgs = Organization.where(id: items.values.map { |v| v[:owner_id] }.uniq).to_a
        Configurable.preload_configuration(orgs)
        org_default_branches = orgs.map { |o| [o.id, o.default_new_repo_branch] }.to_h

        items.each do |id, item|
          log_or_puts("Required workflows transition: starting work on required workflow #{id}, details: #{item.inspect}")

          unless should_continue?(id, item)
            unsuccessful_items << id
            next
          end

          if dry_run?
            # on dry run, we need to build out the ruleset & associations up front to avoid false positive validation errors
            # caused by validations that span across multiple associations (e.g. rule_config raises when ruleset.source is missing)

            ruleset = make_ruleset(item)
            rule_config = ruleset.rule_configurations.build(make_rule_config_hash(item))
            target_branch_condition = ruleset.conditions.build(make_branch_condition_hash(org_default_branches[item[:owner_id]]))

            target_repo_condition_hash = make_repo_condition_hash(id, item, required_workflow_target_repos[id], repos)
            target_repo_condition = ruleset.conditions.build(target_repo_condition_hash) if !target_repo_condition_hash.nil?
          else
            # for the real run, we need to be able to skip validations using `.save!(validate: false)`
            # unfortunately this doesn't seem to apply to downstream associations so we have to save all of the associations individually

            ruleset = make_ruleset(item)
            rule_config = RepositoryRuleConfiguration.new(make_rule_config_hash(item))
            target_branch_condition = RepositoryRuleCondition.new(make_branch_condition_hash(org_default_branches[item[:owner_id]]))

            target_repo_condition_hash = make_repo_condition_hash(id, item, required_workflow_target_repos[id], repos)
            target_repo_condition = RepositoryRuleCondition.new(target_repo_condition_hash) if !target_repo_condition_hash.nil?
          end

          # save the ruleset
          if dry_run?
            log_or_puts("Required workflows transition: would have saved ruleset for required workflow #{id}, details: #{ruleset.inspect}")
          else
            write_to(model_class: RepositoryRuleset) do
              begin
                ruleset.save!
              rescue => e # rubocop:disable Lint/GenericRescue
                log_or_puts("Required workflow transition error: error while saving ruleset for required workflow #{id}: #{e}")
                unsuccessful_items << id
              end
            end

            next if unsuccessful_items.include?(id)
          end

          # add the ruleset id onto the associations
          rule_config.repository_ruleset_id = ruleset.id
          target_branch_condition.repository_ruleset_id = ruleset.id
          target_repo_condition.repository_ruleset_id = ruleset.id unless target_repo_condition.nil?

          # save all the associations, bypassing validations
          if dry_run?
            log_or_puts("Required workflows transition: would have saved rule config for required workflow #{id}, details: #{rule_config.inspect}")
          else
            write_to(model_class: RepositoryRuleConfiguration) do
              begin
                rule_config.save!(validate: false)
              rescue => e # rubocop:disable Lint/GenericRescue
                log_or_puts("Required workflows transition error: error when saving rule config for required workflow #{id}: #{e}")
                unsuccessful_items << id
              end

              next if unsuccessful_items.include?(id)
            end
          end

          if dry_run?
            log_or_puts("Required workflows transition: would have saved target branch condition for required workflow #{id}, details: #{target_branch_condition.inspect}")
          else
            write_to(model_class: RepositoryRuleCondition) do
              begin
                target_branch_condition.save!(validate: false)
              rescue => e # rubocop:disable Lint/GenericRescue
                log_or_puts("Required workflows transition error: error when saving target branch condition for required workflow #{id}: #{e}")
                unsuccessful_items << id
              end
            end

            next if unsuccessful_items.include?(id)

          end

          if !target_repo_condition.nil?
            if dry_run?
              log_or_puts("Required workflows transition: would have saved target repo condition for required workflow #{id}, details: #{target_repo_condition.inspect}")
            else
              write_to(model_class: RepositoryRuleCondition) do
                begin
                  target_repo_condition.save!(validate: false)
                rescue => e # rubocop:disable Lint/GenericRescue
                  log_or_puts("Required workflows transition error: error when saving target repo condition for required workflow #{id}: #{e}")
                  unsuccessful_items << id
                end
              end

              next if unsuccessful_items.include?(id)
            end
          end

          # nothing went wrong saving the ruleset & associations
          # so we can add the required workflow to the list of successful items
          successful_items << id

          valid = if GitHub.enterprise?
            item[:state] == "active"
          else
            false
          end

          if !GitHub.enterprise?
            # determine if everything is valid so we know whether to make the ruleset active
            begin
              valid = ruleset.valid? && rule_config.valid? && target_branch_condition.valid? && (target_repo_condition.nil? || target_repo_condition.valid?)
            rescue => e # rubocop:disable Lint/GenericRescue
              log_or_puts("Required workflows transition error: unexpected error when validating required workflow #{id}: #{e}")
              # we will just treat it as invalid because we don't want to make the ruleset active if we can't validate it
              valid = false
            end
          end

          if valid
            log_or_puts("Required workflows transition: all validations passed for required workflow #{id}")
            valid_ruleset_ids << ruleset.id
          else
            # something is invalid, so we won't make the ruleset active. log the errors and move on
            log_or_puts("Required workflows transition validation error: some validations failed for required workflow #{id}")
            log_or_puts("Required workflows transition validation error: ruleset errors: #{ruleset.errors.full_messages}") if ruleset.errors.any?
            log_or_puts("Required workflows transition validation error: rule config errors: #{rule_config.errors.full_messages}") if rule_config.errors.any?
            log_or_puts("Required workflows transition validation error: target repo condition errors: #{target_repo_condition.errors.full_messages}") if !target_repo_condition.nil? && target_repo_condition.errors.any?
            log_or_puts("Required workflows transition validation error: target branch condition errors: #{target_branch_condition.errors.full_messages}") if target_branch_condition.errors.any?
          end
        end

        # now soft delete the successfully migrated workflows
        if dry_run?
          log_or_puts("Required workflows transition: would have soft deleted #{successful_items.count} required workflows")
          log_or_puts("Required workflows transition: would have set #{valid_ruleset_ids.count} rulesets to active")
        else
          write_to(model_class: RequiredWorkflow) do
            begin
              log_or_puts("Required workflows transition: soft deleting #{successful_items.count} required workflows")
              RequiredWorkflow.where(id: successful_items).update_all({ state: "deleted" })
            rescue => e # rubocop:disable Lint/GenericRescue
              log_or_puts("Required workflows transition errors: error when soft deleting required workflows: #{e}")
              return # so that we don't enable the rulesets if soft delete fails
            end
          end

          write_to(model_class: RepositoryRuleset) do
            begin
              log_or_puts("Required workflows transition: setting #{valid_ruleset_ids.count} rulesets to active")
              RepositoryRuleset.where(id: valid_ruleset_ids).update_all({ enforcement: 1 }) # active
            rescue => e # rubocop:disable Lint/GenericRescue
              log_or_puts("Required workflows transition errors: error when setting new rulesets to active: #{e}")
            end
          end
        end

        log_or_puts("Required workflows transition: successful_items in this batch: #{successful_items}")
        log_or_puts("Required workflows transition: unsuccessful_items in this batch: #{unsuccessful_items}")
      end

      private

      sig do
        params(
          message: String,
        ).void
      end
      def log_or_puts(message)
        # workaround to make transition easier to debug in a codespace
        if ENV["CODESPACES"] == "true"
          puts(message)
          puts("")
        else
          log(message)
        end
      end

      sig do
        params(
          path: String,
        ).returns(T::Boolean)
      end
      def is_invalid_path?(path)
        return true unless path.start_with?(".github/workflows/")
        return true unless path.split("/").length == 3
        false
      end

      sig do
        params(
          id: T.any(Numeric, String),
          item: T::Hash[Symbol, T.untyped]
        ).returns(T::Boolean)
      end
      def should_continue?(id, item)
        # skip if state is "deleted" or it is locked
        # "deleted" state means it was soft deleted (probably by us, in a previous run of the transition)
        # "locked" flag means that someone just edited it and background job has not yet processed the record

        if item[:state] == "deleted"
          # we already processed this record
          return false
        elsif item[:locked]
          log_or_puts("Required workflows transition: skipping required workflow #{id} because it is locked")
          return false
        end
        true
      end

      sig do
        params(
          item: T::Hash[Symbol, T.untyped]
        ).returns(RepositoryRuleset)
      end
      def make_ruleset(item)
        ruleset = RepositoryRuleset.new
        ruleset.name = "Required workflow: #{item[:name]} (Imported by GitHub)"

        # make sure the name isn't already taken
        name_counter = 1
        while RepositoryRuleset.where(source_id: item[:owner_id], source_type: "User", name: ruleset.name).count > 0
          name_counter += 1
          ruleset.name = "Required workflow: #{item[:name]} #{name_counter} (Imported by GitHub)"
        end

        ruleset.source_id = item[:owner_id]
        ruleset.source_type = "User" # because orgs are actually users
        ruleset.enforcement = 0 # disabled
        ruleset.target = "branch"

        ruleset
      end

      sig do
        params(
          item: T::Hash[Symbol, T.untyped]
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def make_rule_config_hash(item)
        rule_config = {}
        rule_config[:rule_type] = "workflows"

        workflow_param = {
          "path": item[:path],
          "repository_id": item[:repository_id]
        }

        if item[:ref].start_with?("ref")
          workflow_param["ref"] = item[:ref]
        else
          workflow_param["sha"] = item[:ref]
        end

        if is_invalid_path?(item[:path])
          workflow_param["allow_invalid_path"] = true
        end

        rule_config[:parameters] = {
          "workflows": [workflow_param]
        }

        rule_config
      end

      sig do
        params(
          id: T.any(Numeric, String),
          item: T::Hash[Symbol, T.untyped],
          repo_ids: T.nilable(T::Array[Integer]),
          repos: T::Hash[Integer, Repository],
        ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def make_repo_condition_hash(id, item, repo_ids, repos)
        target_repo_condition = {}
        target_repo_condition[:condition_type] = "fnmatch"

        if item[:scope] == "all" # all repos
          target_repo_condition[:target] = "repository_name"
          target_repo_condition[:parameters] = { "exclude": [], "include": ["~ALL"] }
        elsif item[:scope] == "selected" # selected repos
          log_or_puts("Required workflows transition errors: no repos found for required workflow with 'selected' scope") if repo_ids.nil?
          return nil if repo_ids.nil?

          target_repo_condition[:target] = "repository_id"
          target_repo_condition[:parameters] = {
            "repository_ids": repo_ids.map { |repo_id| GitHub.enterprise? ? T.must(repos[repo_id]).global_relay_id : T.must(repos[repo_id]).next_global_id }
          }
        end

        target_repo_condition
      end

      sig do
        params(
          org_default_branch: String
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def make_branch_condition_hash(org_default_branch)
        target_branch_condition = {}
        target_branch_condition[:condition_type] = "fnmatch"
        target_branch_condition[:target] = "ref_name"
        target_branch_condition[:parameters] = {
          "exclude": [],
          "include": ["refs/heads/#{org_default_branch}"]
        }

        target_branch_condition
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::MigrateRequiredWorkflowsToRulesets.new(args).run
end
