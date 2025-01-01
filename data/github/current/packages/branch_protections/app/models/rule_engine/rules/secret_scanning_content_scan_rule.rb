# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    # Secret Scanning Content Scan rule
    # Performs an arbitrary content scan (also known as ScanBytes) and fails if any secrets are detected
    # This rule is used for non CLI push flows (file editor UX, file uploads, etc.)
    # Note: this is a COMPANION RULE to SecretScanningRule
    class SecretScanningContentScanRule < CommitRule
      include SecretScanning::Constants

      RULE_NAME = "secret_scanning_content_scan"
      OWNER_TYPE_ORG = "organization"
      OWNER_TYPE_ENTERPRISE = "enterprise"

      def initialize
        super(rule_name: RULE_NAME, display_name: "Check for secrets on push")
      end

      sig { override.params(context: RuleEvaluationContext, rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def skip_evaluation?(context, rule_config)
        # Do nothing if the actor isn't set.
        return true if context.actor.nil?

        # We only want to run this rule from the UI, API etc. not for commit refs
        context.commit_refs_evaluation?
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_configs: T::Array[RepositoryRuleConfiguration],
          candidates: T::Array[MetadataSources::Types::Candidate],
        ).returns(T::Hash[RepositoryRuleConfiguration, T::Array[EvaluationResult]])
      end
      def bulk_evaluate_candidates(context, ref_update, rule_configs, candidates)
        GitHub.dogstats.increment("secret_scanning.push_protection.rule_engine.content_scan")
        super(context, ref_update, rule_configs, candidates)
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_config: RepositoryRuleConfiguration,
          candidate: MetadataSources::Types::Candidate,
        ).returns(EvaluationResult)
      end
      def evaluate_candidate(context, ref_update, rule_config, candidate)
        candidate = T.cast(candidate, RuleEngine::MetadataSources::Types::BlobCandidate)

        if candidate.contents.nil? || candidate.contents&.empty?
          return EvaluationResult.new(candidate: candidate, success: true)
        end

        unless context.blob_evaluation?
          # To satisfy path exclusions, we need to require the path to be set only when the request did not initiate from the blob evaluation event (blob create API)
          if candidate.path.nil? || candidate.path&.empty?
            return EvaluationResult.new(candidate: candidate, success: true)
          end
        end

        actor = T.must(context.actor)
        use_delegated_bypass_flow = SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(context.repository, actor)
        result = SecretScanning::Services::PushProtectionService.scan_content(
          T.must(candidate.contents),
          context.repository,
          T.must(context.actor),
          candidate.path,
          delegated_bypass_enabled: use_delegated_bypass_flow,
        )

        if result.secrets.empty?
          # The scan was successful
          # If any delegated bypass requests were used in the scan, update the request status
          result.used_delegated_bypass_request_ids.each do |bypass_request_id|
            exemption_request = Exemptions::ExemptionRequest.find_by(id: bypass_request_id)
            if exemption_request.nil?
              Failbot.report(SecretScanning::Errors::Error.new("ExemptionRequest not found for bypass_request_id"), app: FAILBOT_APP_NAME, bypass_request_id: bypass_request_id)
              next
            end
            exemption_request.status = :completed
            exemption_request.save!
          end
        end

        EvaluationResult.new(
          candidate: candidate,
          success: result.secrets.empty?,
          metadata: result
        )
      end

      sig do
        override
        .params(
          context: RuleEngine::RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_config: RepositoryRuleConfiguration,
          violations: T::Array[Violation]
        )
        .returns(RuleEngine::RuleRun)
      end
      def generate_evaluation_result(context, ref_update, rule_config, violations)
        return RuleRun.success(rule_config: rule_config, ref_update: ref_update) if violations.empty?

        evaluation_metadata = {}
        evaluation_metadata[SecretScanning::Constants::CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY] = {}
        out_violations = []

        violations.each do |violation|
          candidate = T.cast(violation.candidate, RuleEngine::MetadataSources::Types::BlobCandidate)
          path = T.must(candidate.path)
          out_violations << { candidate: path }
          evaluation_metadata[SecretScanning::Constants::CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY][path] = violation.metadata
        end

        custom_message = owner_custom_resource_message(context.repository)

        RuleRun.failure(
          rule_config: rule_config,
          ref_update: ref_update,
          message: "Secret detected in content#{custom_message.present? ? ". #{custom_message}" : ""}",
          violations: out_violations,
          evaluation_metadata: evaluation_metadata,
        )
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_metadata_types
        [:blob]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:push]
      end

      private

      sig { params(repository: Repository).returns(String) }
      def owner_custom_resource_message(repository)
        data = SecretScanning::Services::PushProtectionService.get_custom_message(repository)
        if data.nil?
          return ""
        end
        "Review a resource from your #{data.owner_type}, #{data.owner_name}: #{data.message}"
      end
    end
  end
end
