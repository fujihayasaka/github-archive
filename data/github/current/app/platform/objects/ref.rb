# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Ref < Objects::Base
      description "Represents a Git reference."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, ref)
        repo = ref.repository
        Promise.all([repo.async_owner, repo.async_parent]).then do |owner, _|
          org = owner.organization? ? owner : nil
          permission.access_allowed?(:get_ref, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_git_object(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:rr, :repository_id, :qualified_name]], as: "REF", uses_database_id: false, ready_date: Platform::Helpers::GlobalId::COHORT_4 do |ref|
        {
          prefix: :rr,
          repository_id: ref.repository.id,
          qualified_name: ref.qualified_name,
        }
      end

      field :repository, Repository, "The repository the ref belongs to.", null: false
      field :name, String, "The ref name.", null: false
      def name
        @object.name.force_encoding("UTF-8")
      end

      field :prefix, String, "The ref's prefix, such as `refs/heads/` or `refs/tags/`.", null: false

      def prefix
        @object.prefix || ""
      end

      field :target, Interfaces::GitObject, "The object the ref points to. Returns null when object does not exist.", null: true

      def target
        Loaders::GitObject.load(@object.repository, @object.target_oid)
      end

      field :directory, Objects::CommittishDirectory, "Look up directory under the commit tree", null: true do
        argument :path, String, "The file path", required: false
      end

      def directory(path: nil)
        revision.async_load_directory(path: path)
      end

      field :file, Objects::CommittishFile, "Look up file under the commit tree.", null: true do
        argument :path, String, "The file path.", required: true
      end

      def file(path:)
        revision.async_load_file(path: path)
      end

      field :associated_pull_requests, resolver: Resolvers::RefPullRequests, description: "A list of pull requests with this ref as the head ref.", null: false

      field :files, Connections.define(Objects::CommittishFile), "Look up a list of files under the commit tree.", null: false do
        argument :paths, [String], "An array of paths in the repository like \"README.md\", \"test.rb\", ...", required: true
      end

      def files(paths:)
        ref = @object
        normalized_paths = paths.map { |p| p.sub(/\A\//, "") }

        files = normalized_paths.map do |path|
          next unless tree_entry = ref.repository.tree_entry(ref.target_oid, path)
          Models::CommittishFile.new(revision, tree_entry, path, ref.target_oid)
        end

        ArrayWrapper.new(files.compact)
      end

      def revision
        @revision ||= Models::CommitRevision.new(@object.repository, @object.name)
      end

      def self.load_from_next_global_id(parsed_id)
        load_from_repo_by_name(parsed_id.parts[:repository_id], parsed_id.parts[:qualified_name])
      end

      def self.load_from_global_id(id)
        repo_id, name = id.split(":", 2)
        load_from_repo_by_name(repo_id, name)
      end

      class << self
        private

        def load_from_repo_by_name(repo_id, name)
          Loaders::ActiveRecord.load(::Repository, repo_id.to_i, security_violation_behaviour: :nil).then do |repo|
            if repo
              repo.async_network.then { repo.refs.find_all([name])[0] }
            end
          end
        end
      end

      field :rules,
        Connections.define(Objects::RepositoryRule),
        minimum_accepted_scopes: ["public_repo"],
        description: "A list of rules from active Repository and Organization rulesets that apply to this ref.",
        null: true,
        connection: true do
          argument :order_by, Inputs::RepositoryRuleOrder,
          "Ordering options for repository rules.",
          required: false,
          default_value: { field: "updated_at", direction: "DESC" }
        end

      def rules(order_by:)
        ref = @object
        repository = ref.repository

        # Manual sanitization
        field = case order_by[:field]
        when "created_at"
          :created_at
        when "updated_at"
          :updated_at
        when "rule_type"
          :rule_type
        else
          :updated_at
        end

        direction = order_by[:direction] == "ASC" ? "ASC" : "DESC"

        # Call async org because the organization association will eventually be called
        Promise.all([repository.async_organization, repository.async_business]).then do
          context = RuleEngine::Conditions::Targets::Ref.new(repository:, ref_name: ref.qualified_name)

          rules = ::RepositoryRuleset.load_for(source: repository, include_parents: true)
            .filter do |ruleset|
              # filter out rulesets that target repositories and don't have
              # member privilege rulesets enabled and specified in the request
              !ruleset.targets_repository? || (
                  ruleset.source.member_privilege_rulesets_enabled? &&
                  @context[:feature_flags].include?(:member_privilege_rulesets)
                )
            end
            .map do |ruleset|
              # only show enabled rules that target this ref
              if ruleset.enabled? && ruleset.should_evaluate?(context)
                # Assigning this source node allows us to authorize the ruleset
                # via the ref's repository, which may be the direct source of the ruleset
                # or inherited from the a higher level ruleset (Organization).
                # As long as the user has the appropriate permissions to view the repo,
                # then they are able to view the ruleset.
                ruleset.source_node = repository
                ruleset.rule_configurations
              end
            end
            .flatten
            .compact

          case order_by[:field]
          when "created_at"
            rules.sort_by! { |rule| rule.created_at }
          when "rule_type"
            rules.sort_by! { |rule| rule.rule_type }
          else
            rules.sort_by! { |rule| rule.updated_at }
          end

          if order_by[:direction] == "DESC"
            rules.reverse!
          end

          ArrayWrapper.new(rules)
        end
      end


      field :branch_protection_rule, Objects::BranchProtectionRule,
        description: "Branch protection rules for this ref",
        null: true,
        method: :protected_branch

      field :viewer_can_commit_to_branch, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Indicates whether the current user is able to commit to a given branch based on permissions and branch protection rules.", null: false

      def viewer_can_commit_to_branch
        @object.repository.async_plan_customer.then do
          @object.repository.resources.contents.writable_by?(@context[:viewer]) &&
            @object.repository.can_commit_to_branch?(@context[:viewer], @object.name)
        end
      end

      field :ref_update_rule, Objects::RefUpdateRule,
        description: "Branch protection rules that are viewable by non-admins",
        method: :protected_branch,
        null: true

      field :updates_channel, String, "Channel value for subscribing to live updates.", null: true, required_capabilities: [:mobile_only_schema_mask, :subscribe_alive_events]

      def updates_channel
        GitHub::WebSocket::Channels.signed_branch(@object.repository, @object.name)
      end

      field :compare, Objects::Comparison, description: "Compares the current ref as a base ref to another head ref, if the comparison can be made.", null: true do
        argument :head_ref, String, "The head ref to compare against.", required: true
      end

      def compare(head_ref:)
        @object.repository.comparison(@object.name, head_ref)
      end
    end
  end
end
