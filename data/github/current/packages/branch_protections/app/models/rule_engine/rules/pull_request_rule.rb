# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class PullRequestRule < RefUpdateRule

      def initialize
        super(
          rule_name: "pull_request",
          display_name: "Require a pull request before merging",
          description: "Require all commits be made to a non-target branch and submitted via a pull request before they can be merged.")
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
        [:creation, :deletion]
      end

      sig { override.params(context: RuleEvaluationContext, policies_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def bulk_evaluate(context, policies_by_ref_update)
        repository = context.repository

        # ref_updates coming from the merge queue ignore the PR policy
        merge_queue_ref_updates = policies_by_ref_update.keys.select do |update|
          queue = context.merge_queue_for(update)
          next false unless queue
          context.merge_queue_head_oids[queue]&.include? update.after_oid
        end

        # Remove ref_updates that are from a merge_queue
        ref_updates = policies_by_ref_update.keys - merge_queue_ref_updates

        # Find the policies that still need to be evaluated
        policies_by_refname = ref_updates.map { |ref_update| [ref_update.refname, policies_by_ref_update[ref_update]] }.to_h

        decisions_by_ref_update = PullRequestReviewRule.check_policies(repository, ref_updates,
          policies_by_refname, actor: context.actor, server_merge: context.server_merge?, cli_merge: context.commit_refs_evaluation?)
          .group_by(&:ref_update)

        policies_by_ref_update.flat_map do |ref_update, rule_configs|
          if merge_queue_ref_updates.include?(ref_update)
            next rule_configs.map { |config| RuleRun.success(rule_config: config, ref_update: ref_update) }
          end

          # Find the decisions for this ref_update and use the sub "rule_decisions" to populate the RuleRuns
          decision = decisions_by_ref_update[ref_update].first
          decision.rule_decisions.map do |config, policy_decision|
            evaluation_metadata = {
              considered_pr_ids: decision&.considered_pull_request_ids || [],
              compliant_pr_ids: decision&.compliant_pull_request_ids || [],
              instrumentation_payload: policy_decision&.instrumentation_payload,
              pr_reviews: decision&.review_statuses.map do |review, status|
                {
                  id: review.id,
                  status: status,
                  state: review.state,
                  reviewer_id: review.user_id,
                }
              end
            }

            if policy_decision.nil? || policy_decision.rules_fulfilled?
              RuleRun.success(rule_config: config, ref_update: ref_update, evaluation_metadata: evaluation_metadata)
            else
              RuleRun.failure(rule_config: config, ref_update: ref_update, message: policy_decision.reason.message,
                evaluation_metadata: evaluation_metadata)
            end
          end
        end
      end

      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Field.new(name: "required_approving_review_count", display_name: "Required approvals",
          type: :integer, required: true,  allowed_range: (0..10),
          description: "The number of approving reviews that are required before a pull request can be merged."))
        schema.add_field(ParameterSchema::Field.new(name: "dismiss_stale_reviews_on_push", display_name: "Dismiss stale pull request approvals when new commits are pushed",
          type: :boolean, required: true, description: "New, reviewable commits pushed will dismiss previous pull request review approvals."))
        schema.add_field(ParameterSchema::Field.new(name: "require_code_owner_review", display_name: "Require review from Code Owners",
          type: :boolean, required: true, description: "Require an approving review in pull requests that modify files that have a designated code owner.", supported_plan: :codeowners))
        schema.add_field(ParameterSchema::Field.new(name: "authorized_dismissal_actors_only", display_name: "Restrict who can dismiss pull request reviews",
          type: :boolean, required: true, description: "Specify people, teams, or apps allowed to dismiss pull request reviews.", org_only: true, internal: true))
        schema.add_field(ParameterSchema::Field.new(name: "require_last_push_approval", display_name: "Require approval of the most recent reviewable push",
          type: :boolean, required: true, description: "Whether the most recent reviewable push must be approved by someone other than the person who pushed it."))
        schema.add_field(ParameterSchema::Field.new(name: "required_review_thread_resolution", display_name: "Require conversation resolution before merging",
            type: :boolean, required: true, description: "All conversations on code must be resolved before a pull request can be merged."))
        schema.add_field(ParameterSchema::Field.new(name: "ignore_approvals_from_contributors", display_name: "Ignore approving reviews from pull request contributors",
          type: :boolean, required: true,
          description: "Pushing to a branch after a pull request is opened will disqualify users from being eligible to approve it.", internal: true))

        schema
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:branch]
      end

      sig do
        override.params(rule_run: RuleRun).returns(T.nilable({
          pr_number: Integer,
          pr_link: String,
          pr_reviewers: T::Array[{
            status: String,
            state_summary: String,
            user: {
              login: String,
              primary_avatar_url: String
            }
          }]
        }))
      end
      def insights_ui_metadata(rule_run)
        if rule_run.evaluation_metadata.present?
          pr_ids = (rule_run.evaluation_metadata["compliant_pr_ids"] || []) + (rule_run.evaluation_metadata["considered_pr_ids"] || [])
          return nil unless pr_ids&.any?

          pr = PullRequest.find_by(id: pr_ids.first)
          return nil unless pr.present?

          metadata = {
            pr_number: T.let(pr.number, Integer),
            pr_link: T.must(pr.permalink),
            pr_reviewers: []
          }

          if rule_run.evaluation_metadata["pr_reviews"]
            users = User.where(id: rule_run.evaluation_metadata["pr_reviews"].map { |r| r["reviewer_id"] }).compact.to_h { |u| [u.id, u] }
            metadata[:pr_reviewers] = rule_run.evaluation_metadata["pr_reviews"].map do |review|
              user = users[review["reviewer_id"]]

              {
                state: PullRequestReview.state_name(review["state"]),
                state_summary: PullRequestReview.new(state: review["state"]).state_summary.humanize,
                user: {
                  login: user&.display_login,
                  primary_avatar_url: user&.primary_avatar_url,
                }
              }
            end
          end

          metadata
        end
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def blocks_new_direct_commits?(rule_config)
        true
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        def pull_request_policy
          configs_by_type("pull_request").first
        end

        def pull_request_policies
          configs_by_type("pull_request")
        end

        def pull_request_required?
          configs_by_type("pull_request").any?
        end
        alias :pull_request_reviews_enabled? :pull_request_required?

        def pull_request_reviews_required?
          pull_request_required? && configs_by_type("pull_request").any? { |c| c.param("required_approving_review_count") > 0 }
        end

        def required_approving_review_count
          configs_by_type("pull_request").map { |c| c.param("required_approving_review_count") }.max
        end

        def ignore_approvals_from_contributors?
          configs_by_type("pull_request").any? { |c| c.param("ignore_approvals_from_contributors") }
        end

        def require_last_push_approval?
          configs_by_type("pull_request").any? { |c| c.param("require_last_push_approval") }
        end

        def dismiss_stale_reviews_on_push?
          configs_by_type("pull_request").any? { |c| c.param("dismiss_stale_reviews_on_push") }
        end

        def require_code_owner_review?
          return false unless repository.plan_supports?(:codeowners)

          configs_by_type("pull_request").any? { |c| c.param("require_code_owner_review") }
        end
        alias :require_code_owner_review :require_code_owner_review?

        def required_review_policy_enforced_for?(actor:)
          configs = configs_by_type("pull_request")
          return false unless configs.any?

          configs.any? { |config| !config.can_bypass?(actor, repository) }
        end

        # Public: Does this protected branch have restricted actors specified for review dismissal?
        #
        # Returns Boolean
        def restricted_dismissed_reviews?
          configs_by_type("pull_request").any? { |c| c.param("authorized_dismissal_actors_only") } && repository.in_organization?
        end

        # Checks to see if the actor who is passed in is in the list of allowed dismissers
        #
        # actor - the current_user viewing the page
        #
        # returns false if the actor is not logged_in
        # returns true if the actor is an admin and admin restrictions are not turned on
        # returns true if actor is in the list of specified users
        # returns true if actor is on one of the specified teams or children of those teams
        def review_dismissable_by?(actor)
          return false unless actor
          unless restricted_dismissed_reviews?
            return repository.pushable_by?(actor)
          end

          configs = configs_by_type("pull_request")

          supports_admin_override = configs.all? do |c|
            c.source.is_a?(ProtectedBranch) && c.source.pull_request_reviews_enforcement_level != "everyone"
          end
          return true if supports_admin_override && repository.resources.administration.writable_by?(actor)

          dismissal_actors = dismissal_restriction_intersection_actors(configs)
          return true if dismissal_actors.include?(actor)

          if actor.is_a?(Bot)
            integration_installations = dismissal_actors.select { |actor| actor.is_a?(IntegrationInstallation) }
            return false unless integration_installations.any?

            return IntegrationInstallation.where(id: integration_installations.map(&:id))
              .joins(:integration)
              .where({ integrations: { id: actor.integration&.id } })
              .any?
          end

          teams = dismissal_actors.select { |actor| actor.is_a?(Team) }
          teams.any? && Team.member_of?(teams.map(&:id), actor.id, immediate_only: false)
        end

        def dismissal_restricted_users
          dismissal_restriction_intersection_actors(configs_by_type("pull_request")).select { |actor| actor.is_a?(User) }
        end

        def dismissal_restricted_teams
          dismissal_restriction_intersection_actors(configs_by_type("pull_request")).select { |actor| actor.is_a?(Team) }
        end

        def dismissal_restricted_integration_installations
          dismissal_restriction_intersection_actors(configs_by_type("pull_request")).select { |actor| actor.is_a?(IntegrationInstallation) }
        end

        private

        # In order to determine if an actor is allowed to dismiss a review, we need to
        # ensure they are in the intersection of all of the dismissal restrictions.
        # Returns the actors that are in the intersection of all dismissal restrictions
        def dismissal_restriction_intersection_actors(rule_configs)
          dismissal_sets = rule_configs.map do |config|
            next [] unless config.source.is_a?(ProtectedBranch) && config.has_param("dismissal_allowances")

            config.param("dismissal_allowances").includes(:actor).map(&:actor).compact
          end

          if dismissal_sets.size > 1
            dismissal_sets.first.intersection(*dismissal_sets.drop(1))
          else
            dismissal_sets.first
          end
        end
      end
    end
  end
end
