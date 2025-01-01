# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    # Secret Scanning Ref Scan rule
    # Performs a git ref scan (also known as ScanPush) and fails if any secrets are detected
    class SecretScanningRule < RefUpdateRule
      include SecretScanning::Features::FeatureFlagHelper
      include SecretScanning::Constants
      RULE_NAME = "secret_scanning"

      def initialize
        super(rule_name: RULE_NAME, display_name: "Secrets detected")
      end

      sig { override.params(context: RuleEvaluationContext, rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def skip_evaluation?(context, rule_config)
        # Do nothing if the actor isn't set.
        return true if context.actor.nil?

        # We only want to run this rule from commit refs, not from the UI, API etc.
        !context.commit_refs_evaluation?
      end

      sig { override.params(context: RuleEvaluationContext, policies_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def bulk_evaluate(context, policies_by_ref_update)
        ref_updates = policies_by_ref_update.keys
        # This is where the push protection itself happens
        actor = T.must(context.actor)
        use_delegated_bypass_flow = SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(context.repository, actor)
        scan_result = SecretScanning::Services::PushProtectionService.scan_ref_updates(ref_updates, context.repository, actor, push_state: context.spokes_push_state, delegated_bypass_enabled: use_delegated_bypass_flow)
        result = []

        if scan_result.secrets.length == 0
          # The scan was successful
          # If any delegated bypass requests were used in the scan, update the request status
          scan_result.used_delegated_bypass_request_ids.each do |bypass_request_id|
            exemption_request = Exemptions::ExemptionRequest.find_by(id: bypass_request_id)
            if exemption_request.nil?
              Failbot.report(SecretScanning::Errors::Error.new("ExemptionRequest not found for bypass_request_id"), app: FAILBOT_APP_NAME, bypass_request_id: bypass_request_id)
              next
            end
            exemption_request.status = :completed
            exemption_request.save!
          end

          return successful_scan_result(policies_by_ref_update)
        end

        # The scan failed, so we need to block the push.
        # Add the scan result to the RuleRun evaluation metadata, so that we can construct the secret scanning CLI message in
        # SecretScanningProvider#on_evaluation_complete

        evaluation_metadata = { RULE_RUN_SCAN_RESULT_METADATA_KEY => scan_result }
        result.concat(policies_by_ref_update.flat_map do |ref_update, policies|
          policies.map do |policy|
            RuleRun.failure(rule_config: policy, ref_update: ref_update, message: SecretScanning::PushProtection::CliConstructor.get_short_message, cli_message: nil, evaluation_metadata: evaluation_metadata)
          end
        end
        )
        result

      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:push]
      end

      sig { override.params(rule_run: RuleRun).returns(T.nilable(Hash)) }
      def insights_ui_metadata(rule_run)
        if rule_run.evaluation_metadata.key?(RULE_RUN_SCAN_RESULT_METADATA_KEY)
          return rule_run.evaluation_metadata[RULE_RUN_SCAN_RESULT_METADATA_KEY]
        end
        if rule_run.evaluation_metadata.key?(CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY)
          return rule_run.evaluation_metadata[CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY]
        end
        # This means the scan was successful, so there's no secret metadata to return.
        nil
      end

      private

      sig { params(policies_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def successful_scan_result(policies_by_ref_update)
        result = []
        result.concat(policies_by_ref_update.flat_map do |ref_update, policies|
          policies.map do |policy|
            RuleRun.success(rule_config: policy, ref_update: ref_update)
          end
        end
        )
        result
      end
    end
  end
end
