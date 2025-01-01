# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module ModifyBranchProtectionRule
        extend T::Helpers

        requires_ancestor { Kernel }

        def update_branch_protection_rule(protected_branch, inputs, context, entry_point:)
          push_actors, dismissal_actors, bypass_pr_actors, bypass_fp_actors = Promise.all([
            Promise.all((inputs[:push_actor_ids] || []).map do |actor_id|
              Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::User, Objects::Team, Objects::App], actor_id, context)
            end),
            Promise.all((inputs[:review_dismissal_actor_ids] || []).map do |actor_id|
              Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::User, Objects::Team, Objects::App], actor_id, context)
            end),
            Promise.all((inputs[:bypass_pull_request_actor_ids] || []).map do |actor_id|
              Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::User, Objects::Team, Objects::App], actor_id, context)
            end),
            Promise.all((inputs[:bypass_force_push_actor_ids] || []).map do |actor_id|
              Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::User, Objects::Team, Objects::App], actor_id, context)
            end),
          ]).sync

          ProtectedBranch.transaction do
            Ability.transaction do
              # Save the record because some methods called below expect it to exist.
              protected_branch.save_with_args!(entry_point: entry_point) if protected_branch.new_record?

              # Enforce code review restrictions.
              if inputs[:requires_approving_reviews] == false
                protected_branch.clear_required_pull_request_reviews
              elsif inputs[:requires_approving_reviews] == true || protected_branch.pull_request_reviews_enabled?
                if protected_branch.admin_enforced?
                  protected_branch.pull_request_reviews_enforcement_level = :everyone
                else
                  protected_branch.pull_request_reviews_enforcement_level = :non_admins
                end

                unless inputs[:dismisses_stale_reviews].nil?
                  protected_branch.dismiss_stale_reviews_on_push = inputs[:dismisses_stale_reviews]
                end

                unless inputs[:requires_code_owner_reviews].nil?
                  protected_branch.require_code_owner_review = inputs[:requires_code_owner_reviews]
                end

                unless inputs[:required_approving_review_count].nil?
                  protected_branch.required_approving_review_count = inputs[:required_approving_review_count]
                end

                if protected_branch.repository.in_organization?
                  if inputs[:restricts_review_dismissals] == false
                    protected_branch.clear_dismissal_restrictions
                  elsif inputs[:restricts_review_dismissals] || (protected_branch.authorized_dismissal_actors_only? && !inputs[:review_dismissal_actor_ids].nil?)
                    protected_branch.replace_dismissal_restricted_actors(
                      user_ids: dismissal_actors.select { |actor| actor.is_a?(::User) }.map(&:id),
                      team_ids: dismissal_actors.select { |actor| actor.is_a?(::Team) }.map(&:id),
                      integration_ids: dismissal_actors.select { |actor| actor.is_a?(::Integration) }.map(&:id),
                    )
                  end
                end

                unless inputs[:require_last_push_approval].nil?
                  protected_branch.require_last_push_approval = inputs[:require_last_push_approval]
                end

                if inputs[:ignore_approvals_from_contributors] == true && protected_branch.repository.disqualify_pr_pushers_from_approving_feature_enabled?
                  protected_branch.ignore_approvals_from_contributors = true
                else
                  protected_branch.ignore_approvals_from_contributors = false
                end

                if protected_branch.repository.in_organization? && !inputs[:bypass_pull_request_actor_ids].nil?
                  if bypass_pr_actors.count == 0
                    protected_branch.clear_branch_actor_allowances(:pull_request)
                  else
                    protected_branch.replace_branch_actor_allowances(
                      :pull_request,
                      user_ids: bypass_pr_actors.select { |actor| actor.is_a?(::User) }.map(&:id),
                      team_ids: bypass_pr_actors.select { |actor| actor.is_a?(::Team) }.map(&:id),
                      integration_ids: bypass_pr_actors.select { |actor| actor.is_a?(::Integration) }.map(&:id),
                    )
                  end
                end
              end

              # Enforce status check restrictions.
              if inputs[:requires_status_checks] == false
                protected_branch.clear_required_status_checks
              elsif inputs[:requires_status_checks] == true || protected_branch.required_status_checks_enabled?
                if protected_branch.admin_enforced?
                  protected_branch.required_status_checks_enforcement_level = :everyone
                else
                  protected_branch.required_status_checks_enforcement_level = :non_admins
                end

                unless inputs[:requires_strict_status_checks].nil?
                  protected_branch.strict_required_status_checks_policy = inputs[:requires_strict_status_checks]
                end

                if !inputs[:required_status_checks].nil?
                  statuses_with_integrations = Promise.all((inputs[:required_status_checks] || []).map do |status|
                    if status[:app_id] == "any"
                      Promise.new.fulfill(context: status[:status_context], source: :any)
                    elsif status[:app_id].present?
                      Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::App], status[:app_id], context).then do |integration|
                        { context: status[:status_context], source: :app, integration: integration }
                      end
                    else
                      Promise.new.fulfill(context: status[:status_context], source: :app, integration: nil)
                    end
                  end).sync
                  protected_branch.replace_statuses(statuses_with_integrations)
                elsif !inputs[:required_status_check_contexts].nil?
                  protected_branch.replace_status_contexts(inputs[:required_status_check_contexts])
                end
              end

              if inputs[:requires_deployments] == false
                protected_branch.clear_required_deployment_environments
              elsif inputs[:requires_deployments] == true || protected_branch.required_deployments_enabled?
                if protected_branch.admin_enforced?
                  protected_branch.required_deployments_enforcement_level = :everyone
                else
                  protected_branch.required_deployments_enforcement_level = :non_admins
                end

                unless inputs[:required_deployment_environments].nil?
                  protected_branch.replace_required_deployment_environments(inputs[:required_deployment_environments])
                end
              end

              if inputs[:requires_conversation_resolution] == true
                protected_branch.enable_required_review_thread_resolution
              elsif inputs[:requires_conversation_resolution] == false
                protected_branch.clear_required_review_thread_resolution
              end

              # Enforce push access restrictions.
              if inputs[:restricts_pushes] == false
                protected_branch.authorized_actors_only = false
              elsif inputs[:restricts_pushes] == true || (protected_branch.has_authorized_actors? && !inputs[:push_actor_ids].nil?)
                protected_branch.replace_authorized_actors(
                  user_ids: push_actors.select { |actor| actor.is_a?(::User) }.map(&:id),
                  team_ids: push_actors.select { |actor| actor.is_a?(::Team) }.map(&:id),
                  integration_ids: push_actors.select { |actor| actor.is_a?(::Integration) }.map(&:id),
                  entry_point: :graphql_api_branch_protection_rule_modify_mutation,
                )
              end

              # Enforce required signatures
              if inputs[:requires_commit_signatures] == true
                protected_branch.enable_required_signatures
              elsif inputs[:requires_commit_signatures] == false
                protected_branch.clear_required_signatures
              end

              # Enforce merge commit prevention
              if inputs[:requires_linear_history] == true
                protected_branch.enable_required_linear_history
              elsif inputs[:requires_linear_history] == false
                protected_branch.clear_required_linear_history
              end

              # Applies to new branch creation
              if inputs[:blocks_creations] == true
                protected_branch.enable_create_protected
              elsif inputs[:blocks_creations] == false
                protected_branch.clear_create_protected
              end

              # Enforce blocking force pushes
              if inputs[:allows_force_pushes] == true
                protected_branch.clear_blocked_force_pushes
              elsif inputs[:allows_force_pushes] == false
                protected_branch.enable_blocked_force_pushes
              end

              if inputs[:lock_branch] == false
                protected_branch.clear_lock_branch
              elsif inputs[:lock_branch] == true || protected_branch.lock_branch_enabled?
                if protected_branch.admin_enforced?
                  protected_branch.lock_branch_enforcement_level = :everyone
                else
                  protected_branch.lock_branch_enforcement_level = :non_admins
                end

                unless inputs[:lock_allows_fetch_and_merge].nil?
                  protected_branch.lock_allows_fetch_and_merge = inputs[:lock_allows_fetch_and_merge]
                end
              end

              if !inputs[:bypass_force_push_actor_ids].nil?
                if bypass_fp_actors.count == 0
                  protected_branch.clear_branch_actor_allowances(:force_push)
                else
                  protected_branch.enable_blocked_force_pushes
                  protected_branch.replace_branch_actor_allowances(
                    :force_push,
                    user_ids: bypass_fp_actors.select { |actor| actor.is_a?(::User) }.map(&:id),
                    team_ids: bypass_fp_actors.select { |actor| actor.is_a?(::Team) }.map(&:id),
                    integration_ids: bypass_fp_actors.select { |actor| actor.is_a?(::Integration) }.map(&:id),
                  )
                end
              end

              # Enforce blocking branch deletion
              if inputs[:allows_deletions] == true
                protected_branch.clear_blocked_deletions
              elsif inputs[:allows_deletions] == false
                protected_branch.enable_blocked_deletions
              end

              # Enforce merge queue
              if inputs[:requires_merge_queue] == true
                protected_branch.enable_merge_queue

                protected_branch.merge_queue_settings_hash = {}
                unless inputs[:merge_queue_check_run_retries].nil?
                  protected_branch.merge_queue_settings_hash[:check_run_retries_limit] = inputs[:merge_queue_check_run_retries]
                end

                unless inputs[:merge_queue_merge_method].nil?
                  protected_branch.merge_queue_settings_hash[:merge_method] = inputs[:merge_queue_merge_method]
                end

                if inputs[:merge_queue_max_entries_to_merge].present?
                  protected_branch.merge_queue_settings_hash[:max_entries_to_merge] = inputs[:merge_queue_max_entries_to_merge]
                elsif inputs[:merge_queue_max_group_size].present?
                  protected_branch.merge_queue_settings_hash[:max_entries_to_merge] = inputs[:merge_queue_max_group_size]
                end

                unless inputs[:merge_queue_min_entries_to_merge].nil?
                  protected_branch.merge_queue_settings_hash[:min_entries_to_merge] = inputs[:merge_queue_min_entries_to_merge]
                end

                unless inputs[:merge_queue_min_entries_to_merge_wait_time].nil?
                  protected_branch.merge_queue_settings_hash[:min_entries_to_merge_wait_minutes] = inputs[:merge_queue_min_entries_to_merge_wait_time]
                end

                unless inputs[:merge_queue_max_entries_to_build].nil?
                  protected_branch.merge_queue_settings_hash[:max_entries_to_build] = inputs[:merge_queue_max_entries_to_build]
                end

                unless inputs[:merge_queue_check_response_timeout].nil?
                  # do not allow 0 as a valid value for this input
                  inputs[:merge_queue_check_response_timeout] = 1 if inputs[:merge_queue_check_response_timeout] < 1
                  protected_branch.merge_queue_settings_hash[:check_response_timeout_minutes] = inputs[:merge_queue_check_response_timeout]
                end

                unless inputs[:merge_queue_merging_strategy].nil?
                  if inputs[:merge_queue_merging_strategy] == "ALLGREEN"
                    protected_branch.merge_queue_settings_hash[:merging_strategy] = "ALLGREEN"
                  else
                    protected_branch.merge_queue_settings_hash[:merging_strategy] = "HEADGREEN"
                  end
                end

              elsif inputs[:requires_merge_queue] == false
                protected_branch.clear_merge_queue
              end

              # Enforce admin restrictions.
              unless inputs[:is_admin_enforced].nil?
                protected_branch.admin_enforced = inputs[:is_admin_enforced]
              end

              protected_branch.save_with_args!(entry_point: entry_point)
            end

            { branch_protection_rule: protected_branch }
          end
        rescue ActiveRecord::RecordInvalid
          raise Errors::Unprocessable.new(protected_branch.errors.full_messages.join(", "))
        rescue ProtectedBranch::OnlyOrgsHaveAuthorizedActors
          raise Errors::Unprocessable.new("Only organization repositories can have users and team restrictions")
        rescue ProtectedBranch::TooManyPermittedActors => e
          raise Errors::Unprocessable.new(e.message)
        end

        def ensure_repo_writable!(repository, context:, operation:)
          raise Errors::Forbidden.new("Upgrade to GitHub Pro or make this repository public to enable this feature.") unless repository.plan_supports?(:protected_branches)
          raise Errors::Forbidden.new("Branch protection #{operation} is disabled on this repository.") unless repository.can_update_protected_branches?(context[:viewer])
          raise Errors::Forbidden.new("Branch protection is disabled on this repository.") if BranchProtectionsConfig.new(repository).branch_protection_disabled?


          raise Errors::Forbidden.new("Repository is archived") if repository.archived?
          # For octoshift repo migrations only, we allow branch protection modification
          raise Errors::Forbidden.new("Repository is locked") if repository.locked? && !(repository.locked_on_migration? || repository.is_importing?)
        end
      end
    end
  end
end
