# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class MergeQueueRule < RefUpdateRule

      sig { void }
      def initialize
        super(rule_name: "merge_queue",
              display_name: "Require merge queue",
              description: "Merges must be performed via a merge queue.")
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:deletion]
      end

      sig { params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        return false unless source.is_a?(::Repository)
        return false unless owner = source.owner
        true
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:repository]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:branch]
      end

      sig { override.returns(Symbol) }
      def supported_plan
        :merge_queue
      end

      # This is a special case because the merge queue rule does not have a feature flag directly on the rule class
      # and we don't want to make the API public yet
      sig { override.returns(T::Boolean) }
      def publish_api
        true
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.15"
      end

      # Some repositories have an exemption from the MQ private beta allowing
      # them to use merge queue even if their plan doesn't support it.
      sig { params(source: RuleEngine::Types::RuleSource, allow_upsell: T::Boolean).returns(T::Boolean) }
      def is_supported_by_plan?(source, allow_upsell: false)
        super || (source.is_a?(::Repository) && source.merge_queue_enabled?)
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(
          validator: method(:ensure_valid_ruleset_configuration),
        )
        merge_queue_defaults = MergeQueues.default_configuration

        schema.add_field(ParameterSchema::Field.new(
          name: "merge_method",
          display_name: "Merge method",
          description: "Method to use when merging changes from queued pull requests.",
          type: :string,
          allowed_options: MergeQueues::IConfiguration::MergeMethod.values.map { { display_name: Configuration.label_for_merge_method(_1), value: _1.serialize.to_s.upcase, description: nil } },
          required: true,
          default_value: merge_queue_defaults.merge_method.serialize.to_s.upcase,
          ui_control: "merge_queue_merge_method",
          validator: method(:ensure_valid_merge_method),
        ))
        schema.add_field(ParameterSchema::Field.new(
          name: "max_entries_to_build",
          display_name: "Build concurrency",
          description: "Limit the number of queued pull requests requesting checks and workflow runs at the same time.",
          type: :integer,
          required: true,
          allowed_range: (0..100),
          ui_prefer_dropdown: false,
          default_value: merge_queue_defaults.max_concurrency,
        ))

        schema.add_field(ParameterSchema::Field.new(
          name: "min_entries_to_merge",
          display_name: "Minimum group size",
          description: "The minimum number of PRs that will be merged together in a group.",
          type: :integer,
          required: true,
          allowed_range: (0..100),
          ui_prefer_dropdown: false,
          default_value: merge_queue_defaults.min_merge_entries_size,
        ))
        schema.add_field(ParameterSchema::Field.new(
          name: "max_entries_to_merge",
          display_name: "Maximum group size",
          description: "The maximum number of PRs that will be merged together in a group.",
          type: :integer,
          required: true,
          allowed_range: (0..100),
          ui_prefer_dropdown: false,
          default_value: merge_queue_defaults.max_merge_entries_size,
        ))
        schema.add_field(ParameterSchema::Field.new(
          name: "min_entries_to_merge_wait_minutes",
          display_name: "Wait time to meet minimum group size (minutes)",
          description: "The time merge queue should wait after the first PR is added to the queue for the minimum group size to be met. After this time has elapsed, the minimum group size will be ignored and a smaller group will be merged.",
          type: :integer,
          required: true,
          allowed_range: (0..360),
          ui_prefer_dropdown: false,
          default_value: (merge_queue_defaults.max_wait_for_min_merge_entries_size.to_i / 60),
        ))
        schema.add_field(ParameterSchema::Field.new(
          name: "grouping_strategy",
          # The UI uses a boolean to toggle between the two grouping strategy values
          # The display name is only used in the UI
          display_name: "Require all queue entries to pass required checks",
          # This description is for the UI only
          description: "When this setting is disabled, only the commit at the head of the merge group, i.e. the commit containing changes from all of the PRs in the group, must pass its required checks to merge.",
          # The API uses enum values for the grouping strategy
          # This description is for the API only
          description_api: "When set to ALLGREEN, the merge commit created by merge queue for each PR in the group must pass all required checks to merge. When set to HEADGREEN, only the commit at the head of the merge group, i.e. the commit containing changes from all of the PRs in the group, must pass its required checks to merge.",
          type: :string,
          required: true,
          allowed_options: MergeQueues::IConfiguration::GroupingStrategy.values.map { { display_name: _1.serialize, value: _1.serialize, description: MergeQueues::IConfiguration::GroupingStrategy.description(_1) } },
          ui_control: "merge_queue_grouping_strategy",
          default_value: merge_queue_defaults.grouping_strategy
        ))
        schema.add_field(ParameterSchema::Field.new(
          name: "check_response_timeout_minutes",
          display_name: "Status check timeout (minutes)",
          description: "Maximum time for a required status check to report a conclusion. After this much time has elapsed, checks that have not reported a conclusion will be assumed to have failed",
          type: :integer,
          required: true,
          allowed_range: (1..360),
          ui_prefer_dropdown: false,
          default_value: (merge_queue_defaults.check_response_timeout.to_i / 60),
        ))
        schema.add_field(ParameterSchema::Field.new(
          name: "check_run_retries_limit",
          display_name: "Check run retry limit",
          description: "The number of additional attempts to get a successful check run",
          type: :integer,
          required: true,
          allowed_range: (0..5),
          feature_flag: :merge_queue_extra_branch_protection_settings,
          visibility_fn: -> (source) do
            source.is_a?(Repository) && source.merge_queue_extra_branch_protection_settings?
          end,
          default_value: merge_queue_defaults.max_attempts,
        ))

        schema.add_field(ParameterSchema::Field.new(
          name: "actor_controlled_merging",
          display_name: "API controlled merging",
          description: "Use the lock and merge GraphQL mutations to control merging, for deploy-then-merge workflows",
          type: :boolean,
          required: false,
          # Currently only available for github
          # But may be released to users later
          feature_flag: :merge_queue_actor_controlled_merging,
          visibility_fn: -> (source) do
            source.is_a?(Repository) && source.github_owned?
          end,
          default_value: merge_queue_defaults.actor_controlled_merging,
        ))

        schema
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_configs: T::Array[RepositoryRuleConfiguration]
        ).returns(T::Array[RuleRun])
      end
      def evaluate(context, ref_update, rule_configs)
        # Multiple merge_queue configurations are not allowed on the same branch
        if context.repository.feature_enabled?(:block_multiple_mq_configs) && rule_configs.size > 1
          return rule_configs.map do |rule_config|
            RuleRun.failure(evaluation_metadata: { bypass_prohibited: true, duplicate_merge_queue: true }, rule_config:, ref_update:,
              message: "Incompatible merge queue rules are configured for this branch")
          end
        end

        merge_queue = context.merge_queue_for(ref_update)
        rule_config = T.must(rule_configs.first)

        # When Merge Queue is not enabled, skip this rule entirely.
        unless merge_queue
          return [RuleRun.success(rule_config:, ref_update:)]
        end

        # Disable the normal PullRequest#merge! behavior because the operation must come from a Merge Queue ref.
        if merge_queue.all_merge_commit_shas.include?(ref_update.after_oid)
          return [RuleRun.failure(evaluation_metadata: { bypass_prohibited: true }, rule_config:, ref_update:,
            message: "Changes must be made through the merge queue")]
        end

        # - The head SHAs from any MergeQueueEntry
        commit_oids_allowed_to_merge = context.merge_queue_head_oids[merge_queue] || Set.new

        # The commit attempting to be merged is in the list of allowed MergeQueue commits OIDs.
        if commit_oids_allowed_to_merge.include?(ref_update.after_oid)
          [RuleRun.success(rule_config:, ref_update:)]
        else
          [RuleRun.failure(rule_config:, ref_update:, message: "Changes must be made through the merge queue")]
        end
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          params: T::Hash[String, T.untyped],
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_valid_ruleset_configuration(context, params, errors)
        ref_targets = context.root["ruleset_ref_targets"]
        return false unless ref_targets

        ref_targets.each do |target|
          if target.match?(ProtectedBranch::CONTAINS_WILDCARD) || target == Conditions::RefNameTarget::ALL_PATTERN
            errors << {
              error_code: :ref_name_wildcard_present,
              message: "Wildcard ref names are not supported when merge queue is enabled"
            }
          end
        end
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          method: String,
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_valid_merge_method(context, method, errors)
        source = context.root["ruleset_source"]
        return unless source.feature_enabled_for_source?(:validate_mq_merge_method)

        selected_method = MergeQueues::IConfiguration::MergeMethod.deserialize(method.downcase.to_sym)
        settings = source.async_allowable_merge_methods.sync

        if settings.get(selected_method).disallowed?
          errors << {
            error_code: :invalid_merge_method,
            message: "Invalid merge method '#{method.downcase}'. Not allowed for this repository.",
            value: method
          }
        end
      end

      # Responsible for translating the untyped configuration data from one or
      # more `RepositoryRuleConfiguration` instances into the typed data
      # used by the Merge Queue engine.
      class Configuration
        include MergeQueues::IConfiguration
        include GitHub::Memoizer

        MERGE_METHOD_LABELS = T.let({
          MergeQueues::IConfiguration::MergeMethod::Merge => "Merge commit",
          MergeQueues::IConfiguration::MergeMethod::Rebase => "Rebase and merge",
          MergeQueues::IConfiguration::MergeMethod::Squash => "Squash and merge",
        }, T::Hash[MergeQueues::IConfiguration::MergeMethod, String])

        sig { params(label: String).returns(MergeQueues::IConfiguration::MergeMethod) }
        def self.merge_method_for_label(label)
          MERGE_METHOD_LABELS.key(label) || MergeQueues.default_configuration.merge_method
        end

        sig { params(merge_method: MergeQueues::IConfiguration::MergeMethod).returns(String) }
        def self.label_for_merge_method(merge_method)
          MERGE_METHOD_LABELS.fetch(merge_method)
        end

        sig { params(configs: T::Array[RepositoryRuleConfiguration], defaults: MergeQueues::IConfiguration).void }
        def initialize(configs:, defaults:)
          @configs = configs
          @defaults = defaults
        end

        sig { override.returns(ActiveSupport::Duration) }
        memoize def max_wait_for_min_merge_entries_size
          config_values("min_entries_to_merge_wait_minutes").max&.minutes ||
            @defaults.max_wait_for_min_merge_entries_size
        end

        sig { override.returns(Integer) }
        memoize def min_merge_entries_size
          config_values("min_entries_to_merge").max || @defaults.min_merge_entries_size
        end

        sig { override.returns(Integer) }
        memoize def max_merge_entries_size
          config_values("max_entries_to_merge").min || @defaults.max_merge_entries_size
        end

        sig { override.returns(Integer) }
        memoize def max_concurrency
          config_values("max_entries_to_build").min || @defaults.max_concurrency
        end

        sig { override.returns(Integer) }
        memoize def max_attempts
          config_values("check_run_retries_limit").min || @defaults.max_attempts
        end

        sig { override.returns(T::Boolean) }
        memoize def actor_controlled_merging
          values = config_values("actor_controlled_merging")
          if values.empty?
            @defaults.actor_controlled_merging
          else
            values.any? { _1 == true }
          end
        end

        sig { override.returns(ActiveSupport::Duration) }
        memoize def check_response_timeout
          config_values("check_response_timeout_minutes").max&.minutes || @defaults.check_response_timeout
        end

        sig { override.returns(MergeQueues::IConfiguration::GroupingStrategy) }
        memoize def grouping_strategy
          values = config_values("grouping_strategy")
          if values.empty?
            return @defaults.grouping_strategy
          end

          if values.any? { _1 == MergeQueues::IConfiguration::GroupingStrategy::AllGreen.serialize }
            MergeQueues::IConfiguration::GroupingStrategy::AllGreen
          else
            MergeQueues::IConfiguration::GroupingStrategy::HeadGreen
          end
        end

        sig { override.returns(MergeQueues::IConfiguration::MergeMethod) }
        memoize def merge_method
          candidates = config_values("merge_method").map { MergeQueues::IConfiguration::MergeMethod.deserialize(_1.downcase.to_sym) }.to_set

          # Priority order: prefer squash or rebase over merge, because they
          # provide more protection against merge base commit smuggling attacks.
          [
            MergeQueues::IConfiguration::MergeMethod::Squash,
            MergeQueues::IConfiguration::MergeMethod::Rebase,
            MergeQueues::IConfiguration::MergeMethod::Merge,
          ].each do |method|
            return method if candidates.include?(method)
          end

          @defaults.merge_method
        end

        private

        sig { params(key: String).returns(T::Array[T.untyped]) }
        def config_values(key)
          @configs.filter_map { _1.param(key) }
        end
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def merge_queue_enabled?
          configs_by_type("merge_queue").any?
        end

        sig { params(actor: T.untyped).returns(T::Boolean) }
        def merge_queue_enforced_for?(actor:)
          config = configs_by_type("merge_queue").first
          return false unless config

          !config.can_bypass?(actor, repository)
        end

        sig { params(defaults: MergeQueues::IConfiguration).returns(MergeQueues::IConfiguration) }
        def merge_queue_configuration(defaults)
          Configuration.new(configs: configs_by_type("merge_queue"), defaults:)
        end
      end
    end
  end
end
