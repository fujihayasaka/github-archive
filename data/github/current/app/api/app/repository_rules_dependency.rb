# typed: true
# frozen_string_literal: true

module Api::App::RepositoryRulesDependency
  extend T::Helpers
  include RepositoryRulesets::HashBuilder

  requires_ancestor { Api::App }

  def update_repository_ruleset(ruleset, data, operation: nil) # rubocop:todo GitHub/UseRestfulActions
    begin
      RepositoryRulesets::HashParser.patch_repository_ruleset!(ruleset, data)
      ruleset
    rescue RepositoryRuleset::ConditionValidationError => e
      deliver_error! 422, errors: e.parse_error_messages
    rescue RepositoryRuleset::RuleValidationError => e
      errors = e.errors.map do |error|
        "Invalid rule '#{error.base.rule_type}': #{error.base.parameter_errors.map { |e| e[:message] }.join(", ")}"
      end
      deliver_error! 422, errors: errors
    rescue RepositoryRuleset::BypassActorsValidationError => e
      failed_actors = e.errors.map { |error| "{{actor_id: #{error.base.actor_id}}, {actor_type: #{error.base.actor_type}}}" }

      deliver_error! 422,
        errors: ["Invalid bypass actor: \'#{failed_actors.uniq.join("\', \'")}\'"]
    rescue RepositoryRulesetBypassActor::ValidationError => e
      deliver_error!(422, errors: e.errors.to_a)
    rescue ActiveRecord::RecordInvalid => e
      deliver_error! 422,
        errors: e.record.errors.full_messages
    rescue RepositoryRuleset::InvalidTarget => e
      # Rescues invalid enums
      deliver_error! 422, errors: e.message
    rescue RepositoryRuleset::Error => e
      deliver_error! 422, errors: e.message
    end
  end

  sig { params(error: StandardError, status: Integer).returns(T.untyped) }
  def deliver_rule_violation_error(error, status)
    doc_url = @documentation_url
    doc_url = GitHub.developer_help_url + doc_url unless doc_url.start_with?("http")
    deliver_raw(
      {
        message: error.detailed_message,
        metadata: get_rule_violation_metadata(error),
        documentation_url: doc_url,
        status: status.to_s,
      },
      status: status,
    )
  end

  sig { params(error: T.nilable(StandardError)).returns(T::Hash[Symbol, T.untyped]) }
  def get_rule_violation_metadata(error)
    return {} unless error.is_a?(Git::Ref::RepositoryRuleViolationError)

    # TODO: the code below is specific to secret scanning, and should be moved into an abstraction
    secret_scanning_runs = error.failed_runs.filter { |r| r.rule_type == RuleEngine::Rules::SecretScanningRule::RULE_NAME }
    return {} if secret_scanning_runs.empty?

    run = T.must(secret_scanning_runs[0])

    scan_results = run.evaluation_metadata[SecretScanning::Constants::CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY]
    return {} if scan_results&.empty?
    scan_result_hash = scan_results.values.first

    result = SecretScanning::Models::SynchronousScanResult.from_hash(scan_result_hash)
    return {} if result.secrets.empty?

    {
      secret_scanning: {
        bypass_placeholders: result.secrets.map do |secret|
          {
            placeholder_id: secret.bypass_placeholder_ksuid,
            token_type: secret.token_metadata.token_type,
          }
        end
      }
    }
  end

  def build_pagination_link_headers(page, per_page, has_next_page)
    @links.add_current({ page: 1, per_page: per_page }, rel: "first") if page > 1
    @links.add_current({ page: page - 1, per_page: per_page }, rel: "prev") if page > 1
    @links.add_current({ page: page + 1, per_page: per_page }, rel: "next") if has_next_page
  end

  def ensure_plan_supports_rules!(repo)
    unless repo.plan_supports?(:protected_branches)
      deliver_error!(403, message: "Upgrade to GitHub Pro or make this repository public to enable this feature.")
    end
  end

  def ensure_plan_supports_org_and_enterprise_rules!(org)
    unless org.plan_supports?(:enterprise_rulesets)
      deliver_error!(403, message: "Upgrade to GitHub Enterprise to enable this feature.")
    end
  end
end
