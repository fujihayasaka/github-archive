# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RequiredStatusCheck < Platform::Objects::Base
      description "Represents an individual required status check for a protected branch."
      mobile_only true

      implements_node templates: [
        [:rrsc, :repo_id, :protected_branch_id, :id],
        [:rcrrsc, :repo_id, :source_type, :source_id, :rule_config_id, :context_hash]
      ], as: "RSC", ready_date: Platform::Helpers::GlobalId::COHORT_5, uses_database_id: false do |required_status_check|
        if required_status_check.protected_branch_backed?
          required_status_check.async_protected_branch.then do |protected_branch|
            protected_branch.async_repository.then do |repository|
              {
                prefix: :rrsc,
                repo_id: repository.id,
                protected_branch_id: protected_branch.id,
                id: required_status_check.id
              }
            end
          end
        else
          {
            prefix: :rcrrsc,
            repo_id: required_status_check.repository.id,
            source_type: required_status_check.source&.class&.name,
            source_id: required_status_check.source&.id,
            rule_config_id: required_status_check.rule_config.id,
            context_hash: required_status_check.context_hash
          }
        end
      end

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]
        if prefix == :rcrrsc
          repo_id = parsed_id.parts[:repo_id]
          rule_config_id = parsed_id.parts[:rule_config_id]
          context_hash = parsed_id.parts[:context_hash]
          load_rule_config_check(repo_id.to_i, rule_config_id.to_i, context_hash)
        elsif prefix == :rrsc
          Platform::Loaders::ActiveRecord.load(::RequiredStatusCheck, parsed_id.id)
        else
          raise(Platform::Errors::NotFound, "Template prefix '#{prefix}' does not match an existing global id template")
        end
      end

      def self.load_from_global_id(id)
        if id.include?(":")
          repo_id, rule_config_id, context_hash = id.split(":", 3)
          load_rule_config_check(repo_id.to_i, rule_config_id.to_i, context_hash)
        else
          Platform::Loaders::ActiveRecord.load(::RequiredStatusCheck, id.to_i)
        end
      end

      def self.load_rule_config_check(repo_id, rule_config_id, context_hash)
        Platform::Loaders::ActiveRecord.load(::Repository, repo_id).then do |repo|
          Platform::Loaders::ActiveRecord.load(::RepositoryRuleConfiguration, rule_config_id).then do |config|
            json_check = config&.param("required_status_checks")&.find do |check|
              InMemoryRequiredStatusCheck.generate_context_hash(check["context"], check["integration_id"]) == context_hash
            end
            if json_check && repo
              status_check = InMemoryRequiredStatusCheck.normalize_status_checks(T.must(config), [json_check])[0]
              Platform::Models::RequiredStatusCheck.new(status_check, repo)
            end
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, status)
        permission.async_repo_and_org_owner(status).then do |repo, org|
          permission.access_allowed?(:read_status, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        if object.protected_branch_backed?
          object.async_protected_branch.then do |protected_branch|
            permission.belongs_to_repository(protected_branch)
          end
        else
          object.async_repository.then do |source|
            permission.typed_can_see?("Repository", source)
          end
        end
      end

      scopeless_tokens_as_minimum

      field :state, Enums::StatusState, "The state of this status.", null: false
      field :context, String, "The name of this status.", resolver_method: :status_context, null: false
      # This field should get the _object's_ context, not the GraphQL query context.
      def status_context
        @object.context
      end

      field :description, String, "The description for this status.", null: true

      created_at_field
    end
  end
end
