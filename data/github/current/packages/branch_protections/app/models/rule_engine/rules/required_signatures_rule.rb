# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RequiredSignaturesRule < RefUpdateRule

      # How many commits to load and signatures to verify at a time.
      SIGNATURE_VERIFICATION_BATCH_SIZE = 1000

      def initialize
        super(rule_name: "required_signatures",
              display_name: "Require signed commits",
              description: "Commits pushed to matching refs must have verified signatures.")
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      def is_user_configurable?(source = nil)
        true
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        # ignore deletions (which have no commits to sign)
        [:deletion]
      end

      # The required signature policy has no configuration: return the same result for each configuration
      sig { override.params(context: RuleEvaluationContext, policies_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def bulk_evaluate(context, policies_by_ref_update)
        repository = context.repository

        rule_runs = []
        has_applicable_configs = T.let(false, T::Boolean)

        applicable_configs_by_ref_update = policies_by_ref_update.each_with_object(T.let({}, T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]])) do |(ref_update, configs), h|
          applicable_configs = configs.filter_map do |config|
            next config if config.provider_name == "protected_branch"

            rule_runs.push(RuleRun.success(rule_config: config, ref_update: ref_update))

            nil
          end

          h[ref_update] = applicable_configs
          has_applicable_configs = true if applicable_configs.any?
        end

        # Prevent unnecessarily loading and verifying commits when there are no applicable configs
        return rule_runs unless has_applicable_configs

        updates = applicable_configs_by_ref_update.keys

        # find oids of commits in ref-update.
        oids_by_update = updates.each_with_object(T.let({}, T::Hash[Git::Ref::Update, T.untyped])) do |ref_update, h|
          h[ref_update] = if ref_update.creation?
            repository.rpc.rev_list(ref_update.after_oid)
          else
            repository.rpc.rev_list(ref_update.after_oid,
              exclude_oids: ref_update.before_oid,
            )
          end
        end

        # load commits.
        oids = oids_by_update.values.flatten.uniq
        batches = oids.each_slice(SIGNATURE_VERIFICATION_BATCH_SIZE)
        commit_by_oid = batches.each_with_object({}) do |slice, h|
          repository.commits.find(slice).each { |c| h[c.oid] = c }
        end
        commits_by_update = oids_by_update.each_with_object(T.let({}, T::Hash[Git::Ref::Update, T.untyped])) do |(ref_update, update_oids), h|
          h[ref_update] = commit_by_oid.values_at(*update_oids)
        end

        # quickly deny ref-updates with a commit having no signature.
        commits_by_update.keep_if do |ref_update, commits|
          violations = commits.filter_map { |commit| { candidate: commit.oid } unless commit.has_signature? }

          if violations.none?
            true
          else
            instrument_required_signatures_check(allowed: false, reasons: [GitSigning::UNSIGNED])

            rule_runs.concat(applicable_configs_by_ref_update[ref_update]&.map do |config|
              RuleRun.failure(
                rule_config: config,
                ref_update: ref_update,
                message: "Commits must have verified signatures.",
                violations:
              )
            end || [])

            false
          end
        end
        return rule_runs if commits_by_update.empty?

        # verify signatures.
        commits = commits_by_update.values.flatten
        commits.each_slice(SIGNATURE_VERIFICATION_BATCH_SIZE) do |slice|
          Commit.prefill_verified_signature(slice, repository, save_to_db: false)
        end

        # deny ref-updates with a commit having invalid signature.
        commits_by_update.each do |ref_update, commits|
          unverified_commits = commits.reject(&:verified_signature?)
          allowed = unverified_commits.none?

          instrument_required_signatures_check(allowed: allowed,
            reasons: unverified_commits.map(&:signature_verification_reason)
          )

          if allowed
            rule_runs.concat(applicable_configs_by_ref_update[ref_update]&.map do |config|
              RuleRun.success(rule_config: config, ref_update: ref_update)
            end || [])
          else
            rule_runs.concat(applicable_configs_by_ref_update[ref_update]&.map do |config|
              RuleRun.failure(
                rule_config: config,
                ref_update: ref_update,
                message: "Commits must have verified signatures.",
                violations: unverified_commits.map { |commit| { candidate: commit.oid } }
              )
            end || [])
          end
        end

        rule_runs
      end

      private

      def instrument_required_signatures_check(allowed:, reasons: [])
        tags = GitSigning::REASONS.map { |r| "#{r}:#{reasons.include?(r)}" }
        tags << allowed ? "result:allow" : "result:deny"

        GitHub.dogstats.increment("repository_rules_engine.rule.required_signatures.check", tags: tags)
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        def required_signatures_enabled?
          configs_by_type("required_signatures").any?
        end

        def can_override_required_signatures?(actor:)
          enforced_rules_by_type("required_signatures", actor).empty?
        end

        def required_signatures_enforced_for?(actor:)
          enforced_rules_by_type("required_signatures", actor).any?
        end
      end
    end
  end
end
