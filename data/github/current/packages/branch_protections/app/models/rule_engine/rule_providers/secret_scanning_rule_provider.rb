# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class SecretScanningRuleProvider < RuleProvider
      include SecretScanning::Features::FeatureFlagHelper
      include SecretScanning::Constants
      include SecretScanning::BypassDelegation
      include GitRuleProvider

      def initialize
        super(identifier: "secret_scanning")
      end

      sig { override.returns(Types::Phase) }
      def phase
        Types::Phase::PreReceive
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[RepositoryRuleConfiguration]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        return [] if GitHub.skip_secret_scanning_in_rules_engine?
        # There must be >= 1 ref update to scan
        return [] if ref_updates.empty?
        # The actor must not be nil
        return [] if actor.nil?
        # Check push protection enablement
        repo_push_protection = SecretScanning::Features::Repo::PushProtection.new(repository)
        push_protection_enabled_for_repo = repo_push_protection.enabled?
        public_push_protection_enabled_for_user = actor.id.present? && SecretScanning::Features::User::PushProtection.new(T.must(actor)).enabled? && repository.public?
        return [] unless push_protection_enabled_for_repo || public_push_protection_enabled_for_user

        [
          RepositoryRuleConfiguration.create_provider_rule(
            provider: self,
            source: repository,
            rule_type: Rules::SecretScanningRule::RULE_NAME,
            matching_ref_names: ref_updates.map(&:refname),
            parameters: {}
          ),
        ]
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        # This is used by the UI, which we're not integrated with right now. So leaving this unimplemented.
        []
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: Types::Actor,
          repository: Repository,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, repository, rule_run = nil)
        # Returns false because we currently handle bypasses outside of the rules engine architecture
        false
      end

      sig { override.params(rule_run: RuleRun).returns(T.nilable(String)) }
      def insights_category(rule_run)
        "System rules"
      end

      sig do
        override.params(
          rule_suite: RuleSuite,
          event: RuleEvent,
        ).void
      end
      def on_evaluation_complete(rule_suite, event)
        actor = event.actor

        failed_runs = rule_suite.rule_runs.filter(&:failed?).filter { |rule_run| rule_run.rule_provider == identifier }
        # There's nothing to do if the RuleSuite succeeded i.e push protection succeeded
        return if failed_runs.empty?

        # But if push protection failed, construct the CLI message and add it to the failed RuleRuns
        repo = rule_suite.repository
        if repo.nil?
          Failbot.report(SecretScanning::Errors::Error.new("No repository for RuleSuite"), app: FAILBOT_APP_NAME, rule_suite_id: rule_suite.id)
          return
        end

        most_recent_rule_run = T.must(failed_runs[-1])
        if most_recent_rule_run.evaluation_metadata[RULE_RUN_SCAN_RESULT_METADATA_KEY].nil?
          # SecretScanningRuleProvider now processes the 2 secret scanning rule types: SecretScanningRule and
          # SecretScanningContentScanRule. They never run together (see the implementations of skip_evaluation? for both).
          # So, if the most recent rule run's metadata doesn't contain the key for SecretScanningRule, skip the
          # rest of this evaluation.
          return
        end

        scan_result = SecretScanning::Models::SynchronousScanResult.from_hash(most_recent_rule_run.evaluation_metadata[RULE_RUN_SCAN_RESULT_METADATA_KEY])

        use_delegated_bypass_flow = SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(repo, actor)
        secret_bypass_placeholder_ksuids_to_urls = construct_secret_to_bypass_url_mapping(rule_suite, repo, actor, scan_result, use_delegated_bypass_flow)
        cli_constructor = SecretScanning::PushProtection::CliConstructor.new(repo, actor, use_delegated_bypass_flow)
        rule_suite.additional_cli_message = cli_constructor.get_long_message(scan_result, secret_bypass_placeholder_ksuids_to_urls)
      end

      sig { params(rule_suite: RuleSuite, repo: Repository, actor: Types::Actor, scan_result: SecretScanning::Models::SynchronousScanResult, use_delegated_bypass_flow: T::Boolean).returns(T::Hash[String, String]) }
      def construct_secret_to_bypass_url_mapping(rule_suite, repo, actor, scan_result, use_delegated_bypass_flow)
        # Construct the secret-to-bypass-URL mapping
        secret_bypass_placeholder_ksuids_to_urls = {}
        if use_delegated_bypass_flow
          scan_result.secrets.each do |secret|
            url = create_secret_scanning_bypass_url(rule_suite.repository, rule_suite.id, T.must(secret.bypass_placeholder_ksuid))
            secret_bypass_placeholder_ksuids_to_urls[secret.bypass_placeholder_ksuid] = url
          end
        else
          scan_result.secrets.each do |secret|
            secret_bypass_placeholder_ksuids_to_urls[secret.bypass_placeholder_ksuid] = UrlHelpers.repository_secret_scanning_push_protection_bypass_placeholder_url(
              host: GitHub.multi_tenant_enterprise? ? GitHub.host_name_with_tenant : GitHub.host_name,
              user_id: repo.owner_display_login,
              repository: repo.name,
              placeholder_ksuid: secret.bypass_placeholder_ksuid,
              protocol: GitHub.scheme
            )
          end
        end
        secret_bypass_placeholder_ksuids_to_urls
      end
    end
  end
end
