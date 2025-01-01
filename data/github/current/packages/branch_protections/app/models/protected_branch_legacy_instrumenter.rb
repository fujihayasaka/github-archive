# typed: true
# frozen_string_literal: true

class ProtectedBranchLegacyInstrumenter
  extend T::Sig

  sig { params(rule_suites: T::Enumerable[RuleEngine::RuleSuite], repository: Repository).void }
  def self.instrument_decision(rule_suites, repository)
    rule_suites.each do |suite|
      instrumentation_payload = instrumentation_payload_for(suite.ref_update, repository, suite.actor, failed_runs: suite.rule_runs.filter(&:failed?),
        additional_payloads: suite.rule_runs.map(&:instrumentation_payload).compact) unless suite.rules_fulfilled?

      suite.legacy_instrument_decision(instrumentation_payload)
    end
  end

  def self.instrumentation_payload_for(ref_update, repository, actor, failed_runs:, additional_payloads: [])
    payload = {
      branch: ref_update.refname,
      repo: repository,
      before: ref_update.before_oid,
      after: ref_update.after_oid,
    }

    if actor.is_a?(PublicKey)
      payload[:actor] = actor.verifier
      payload[:deploy_key_fingerprint] = actor.fingerprint
    else
      payload[:actor] = actor
    end

    payload[:reasons] = failed_runs.sort_by(&:legacy_reason_code).map do |run|
      {
        code: run.legacy_reason_code,
        message: run.message,
      }
    end

    if ref_update.respond_to?(:policy_commit_oid)
      payload[:policy] = ref_update.policy_commit_oid
    end

    if repository.in_organization?
      payload[:org] = repository.organization
    end

    additional_payloads.each do |additional_payload|
      payload.merge!(additional_payload)
    end

    payload
  end
end
