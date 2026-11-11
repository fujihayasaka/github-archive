# typed: strict
# frozen_string_literal: true

require "hydro/schemas/turboquality/v0/pull_request_analysis_pb"

module RuleEngine
  module Rules
    class CodeQualityRule < RefUpdateRule

      RULE_SEVERITY_NOTE = "notes"
      RULE_SEVERITY_WARNING = "warnings"
      RULE_SEVERITY_ERROR = "errors"
      RULE_SEVERITY_ALL = "all"

      SEVERITIES_FOR_AUTOMATED_REVIEW = T.let({
        RULE_SEVERITY_ALL => 0, # Block everything (>= 0, i.e., all severities)
        RULE_SEVERITY_NOTE => AutomatedReviewComment.severities[:severity_note], # Block notes and above (>= 1)
        RULE_SEVERITY_WARNING => AutomatedReviewComment.severities[:severity_warning], # Block warnings and above (>= 2)
        RULE_SEVERITY_ERROR => AutomatedReviewComment.severities[:severity_error], # Block only errors (>= 3)
      }, T::Hash[String, Integer])

      CCR_SEVERITY_NONE = "none"
      CCR_SEVERITY_NIT = "nit"
      CCR_SEVERITY_MEDIUM = "medium"
      CCR_SEVERITY_HIGH = "high"

      CCR_SEVERITIES_FOR_AUTOMATED_REVIEW = T.let({
        CCR_SEVERITY_NIT => AutomatedReviewComment.severities[:severity_nit],       # Block nit and above
        CCR_SEVERITY_MEDIUM => AutomatedReviewComment.severities[:severity_medium], # Block medium and above
        CCR_SEVERITY_HIGH => AutomatedReviewComment.severities[:severity_high],     # Block only high
      }, T::Hash[String, Integer])

      sig { void }
      def initialize
        super(
          rule_name: "code_quality",
          beta: false,
          feature_flag: :code_quality,
          display_name: "Require code quality results",
          description: "Choose which severity levels of code quality results should block pull request merges. When configured, a code quality analysis must be done on the pull request before the changes can be merged.",
        )
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.18"
      end

      sig { override.returns(ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })

        review_severity = ParameterSchema::Field.new(name: "severity", display_name: "Severity",
          type: :string, required: true, description: "The lowest severity level at which code quality reviews need to be resolved before commits can be merged.", default_value: RULE_SEVERITY_ERROR, allowed_options: [
            { value: RULE_SEVERITY_ERROR, display_name: "Errors", description: nil },
            { value: RULE_SEVERITY_WARNING, display_name: "Warnings and higher", description: nil },
            { value: RULE_SEVERITY_NOTE, display_name: "Notes and higher", description: nil },
            { value: RULE_SEVERITY_ALL, display_name: "All", description: nil },
          ])

        schema.add_field(review_severity)

        ai_findings_severity = ParameterSchema::Field.new(
          name: "ai_findings_severity",
          display_name: "AI findings severity threshold",
          type: :string,
          required: false,
          description: "The lowest severity level of Copilot code review findings that must be resolved before the pull request can be merged.",
          feature_flag: :code_quality_evaluate_ccr_comments,
          default_value: CCR_SEVERITY_NONE,
          allowed_options: [
            { value: CCR_SEVERITY_NONE, display_name: "None (do not block)", description: nil },
            { value: CCR_SEVERITY_HIGH, display_name: "High", description: nil },
            { value: CCR_SEVERITY_MEDIUM, display_name: "Medium and higher", description: nil },
            { value: CCR_SEVERITY_NIT, display_name: "Nit and higher", description: nil },
          ],
        )

        schema.add_field(ai_findings_severity)
        schema
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:branch]
      end

      sig { override.params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.params(rule_config: IRuleConfig).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:creation, :deletion]
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[IRuleConfig]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        all_succeeded = rule_configs.map { |rule_config| RuleRun.success(rule_config:, ref_update:) }

        # If the ref update is not a branch update, we don't need to check for a code quality review
        return all_succeeded unless ref_update.is_a?(Git::Branch::Update)

        # If the ref update isn't for a pull request, we don't need to check for a code quality review
        pull_request = ref_update.pull_request
        return all_succeeded unless pull_request.present?

        # Skip evaluation if the repository does not have code quality enabled
        repository = context.repository
        return all_succeeded unless CodeQuality.enabled?(repository)

        # Skip evaluation if Dependabot is the author and last pusher of the pull request since managed analyses
        # don't run on Dependabot PRs/commits, and Dependabot doesn't make code changes.
        is_dependabot = ->(author) { author&.bot? && author&.is_dependabot? }
        return all_succeeded if GitHub.dependabot_enabled? &&
                is_dependabot[pull_request.user] &&
                is_dependabot[
                  Repositories.domain.pushes.latest_by_after_and_ref(
                    repository_id: pull_request.repository_id,
                    ref: "refs/heads/#{pull_request.head_ref_name}",
                    after: pull_request.head_sha,
                  )&.pusher
                ]

        pending_languages = CodeQualityPullRequestAnalyses.pending_languages(repository: repository, pull_request: pull_request, commit_oid: pull_request.head_sha)
        unless pending_languages.empty?
          msg = if pending_languages.count == 1
            "Code quality results are pending for one analyzed language."
          else
            "Code quality results are pending for #{pending_languages.count} analyzed languages."
          end
          return rule_configs.map do |rule_config|
            RuleRun.failure(rule_config:, ref_update:, message: msg)
          end
        end

        cq_results = evaluate_with_automated_review_comments(
          repository:,
          pull_request:,
          all_succeeded:,
          rule_configs:,
          ref_update:,
        )

        # Evaluate CCR (Copilot Code Review) comments if the feature flag is enabled
        ccr_results = if FeatureFlag.vexi.enabled?(:code_quality_evaluate_ccr_comments, repository, default: false)
          evaluate_with_ccr_comments(
            repository:,
            pull_request:,
            rule_configs:,
            ref_update:,
          )
        end

        merge_cq_and_ccr_results(cq_results, ccr_results)
      end

      sig { override.params(rule_config: IRuleConfig).returns(T::Boolean) }
      def blocks_new_direct_commits?(rule_config)
        true
      end

      private

      sig { params(cq_results: T::Array[RuleRun], ccr_results: T.nilable(T::Array[RuleRun])).returns(T::Array[RuleRun]) }
      def merge_cq_and_ccr_results(cq_results, ccr_results)
        return cq_results if ccr_results.nil?

        cq_results.zip(ccr_results).map do |cq_run, ccr_run|
          if cq_run.result == "failed"
            cq_run
          elsif ccr_run&.result == "failed"
            T.must(ccr_run)
          else
            cq_run
          end
        end
      end

      sig { params(repository: Repository, pull_request: T.untyped, all_succeeded: T::Array[RuleRun], rule_configs: T::Array[IRuleConfig], ref_update: Git::Ref::Update).returns(T::Array[RuleRun]) }
      def evaluate_with_automated_review_comments(repository:, pull_request:, all_succeeded:, rule_configs:, ref_update:)
        # Get all code quality automated comments for the pull request
        automated_comments = AutomatedReviewComment.where(
          repository:,
          pull_request:,
          source: :source_code_quality,
          fixed_at: nil,
          dismissed_at: nil,
        )

        # no unfixed automated comments -> success
        return all_succeeded if automated_comments.empty?

        rule_configs.map do |rule_config|
          rule_config_severity = rule_config.parameters.fetch("severity", RULE_SEVERITY_ALL)
          max_permissable_severity = SEVERITIES_FOR_AUTOMATED_REVIEW[rule_config_severity]

          next RuleRun.failure(rule_config:, ref_update:, message: "Severity #{rule_config_severity} not known") if max_permissable_severity.nil?

          automated_comments_block_merge = automated_comments.any? do |automated_comment|
            automated_comment_severity_value = AutomatedReviewComment.severities[automated_comment.severity]

            # If we cannot determine the severity of the finding, assume it blocks the merge
            next true if automated_comment_severity_value.nil?

            automated_comment_severity_value >= max_permissable_severity
          end

          if automated_comments_block_merge
            message = if rule_config_severity == RULE_SEVERITY_ALL
              "Code quality findings were detected."
            else
              "Code quality findings with severity of #{rule_config_severity.singularize} or above were detected."
            end
            RuleRun.failure(rule_config:, ref_update:, message:)
          else
            RuleRun.success(rule_config:, ref_update:)
          end
        end
      end

      sig { params(repository: Repository, pull_request: T.untyped, rule_configs: T::Array[IRuleConfig], ref_update: Git::Ref::Update).returns(T::Array[RuleRun]) }
      def evaluate_with_ccr_comments(repository:, pull_request:, rule_configs:, ref_update:)
        ccr_comments = AutomatedReviewComment.where(
          repository:,
          pull_request:,
          source: :source_copilot,
          fixed_at: nil,
          dismissed_at: nil,
        )

        rule_configs.map do |rule_config|
          ai_severity = rule_config.parameters["ai_findings_severity"]
          next RuleRun.success(rule_config:, ref_update:) if ai_severity.nil? || ai_severity == CCR_SEVERITY_NONE

          max_permissable_severity = CCR_SEVERITIES_FOR_AUTOMATED_REVIEW[ai_severity]
          next RuleRun.failure(rule_config:, ref_update:, message: "AI findings severity #{ai_severity} not known") if max_permissable_severity.nil?
          next RuleRun.success(rule_config:, ref_update:) if ccr_comments.empty?

          blocks_merge = ccr_comments.any? do |comment|
            severity_value = AutomatedReviewComment.severities[comment.severity]
            next true if severity_value.nil?
            severity_value >= max_permissable_severity
          end

          if blocks_merge
            RuleRun.failure(rule_config:, ref_update:, message: "Copilot code review findings with severity of #{ai_severity} or above were detected.")
          else
            RuleRun.success(rule_config:, ref_update:)
          end
        end
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        sig { returns(T::Boolean) }
        def code_quality_enabled?
          configs_by_type("code_quality").any?
        end
      end
    end
  end
end
