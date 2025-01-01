# typed: strict
# frozen_string_literal: true

module Issues
  module Comments
    extend self

    PRELOAD_FEATURES = T.let([
      :active_job_skip_enqueue,
      :adaptive_card_markdown_parsing,
      :add_oauth_app_to_dog_tags,
      :aqueduct_enqueue_to_gateway,
      :aqueduct_enqueue_to_secondary,
      :belongs_to_repo_domain,
      :gitrpc_always_include_request_id,
      :emit_redis_command_size_metric,
      :html_pipeline_bad_emoji,
      :hydro_async_sink,
      :insights_enabled_staging,
      :insights_publish_enabled,
      :instrument_rails_callbacks,
      :interaction_limit_kv_fallback,
      :issue_comments_spam_check,
      :issue_touch_pull_request_after_commit,
      :publish_events_to_notifyd,
      :reserved_domain,
      :secure_user_assets_auth_check,
      :secure_user_assets,
      :spokesd_cache_key,
      :spokesd_request_timeout_header_spokes_api,
      :tasklist_block_markdown_at_rest,
      :tasklist_block_nested_html_pipeline,
      :disable_track_tasklist_blocks,
      :tasklist_block_precache,
      :tasklist_block,
      :token_scanning_scan_all_token_types_public,
      :track_issue_and_pr_references_in_background,
      :issue_track_tasklist_blocks_on_body_update_only,
      :user_generated_content_hydro_publisher,
      :disable_mathjax,
      :throttle_expensive_gitrpc_calls, # enables throttling for expensive gitrpc calls
      :private_avatars,
      :via_domain_singleton,
      :active_job_default_to_write_connection,
      :active_job_replica_clusters_only,
      :check_reference_exists,
      :split_ability_loader,
      :run_split_ability_loader_experiment,
      :repo_network_domain,
      :report_authzd_indeterminates,
      :attach_repository_files,
      :authzd_test_flag,
      :issue_comment_update_use_orchestration,
      :sync_pr_status_in_orchestration,
      :skip_model_importing_check_on_old_repositories,
      :enterprise_teams_attributes_include_business_teams,
      :sync_issue_state_to_pull_request,
      :use_authzd_mesh_client, # use the authzd mesh client for authzd requests
      :spokesd_instrumenter_collector, # enables spokesd instrumenter collector
      :throttle_pushes_on_both_clusters,
      :vitess_append_max_execution_time_comment_issues_pull_requests, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
      :vitess_use_new_max_execution_time_issues_pull_requests, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
      :vitess_append_max_execution_time_comment_repositories, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries
      :vitess_use_new_max_execution_time_repositories, # appends MAX_EXECUTION_TIME optimizer hint to relevant queries, using the new timeout value
      :users_by_id_cache_interface,
      :issue_comments_api_use_mysql1_replica,
      :verbose_add_to_search_index_logging,  # Emits logs for Search.add_to_search_index
      :remove_bill_mgr_internal_repo, # authzd internal repo access macro tests
      :application_record_attribute_access_telemetry,
    ].freeze, T::Array[Symbol])

    sig { params(comment: IssueComment, body: String, editor: User, performed_via_integration: T.nilable(Integration)).returns(T::Boolean) }
    def update_comment(comment, body, editor, performed_via_integration: nil)
      FeatureFlag.vexi.preload PRELOAD_FEATURES, instrumentation_properties: {
        "code.namespace": "issues_comments",
      }
      replica_clusters = [ApplicationRecord::Collab]
      ActiveRecord::Base.connected_to_many(replica_clusters, role: :reading) do
        !!comment.update_body(body, editor, performed_via_integration: performed_via_integration)
      end
    end

    sig { params(comment: IssueComment, actor: T.nilable(User)).returns(T::Boolean) }
    def delete(comment, actor = nil)
      comment.skip_delete_issue_comment_orchestration = true

      orchestration = T.let(nil, T.nilable(DeleteIssueCommentOrchestration))

      success = IssueCommentOrchestration.transaction do
        # Validate that the comment hasn't already been deleted by another request (race condition).
        # This needs to run in the same transaction as the actualy destroy call below.
        next false if IssueComment.where(id: comment.id).empty?

        next false unless comment.destroy

        # Create orchestration within the same transaction for consistency (outbox pattern)
        orchestration = IssueCommentOrchestration.delete_issue_comment!(comment: comment, actor: actor, uses_domain: true)
        true
      end

      # Execute orchestration outside of the transaction to avoid long-running transactions and lock contention
      orchestration.execute! if success && orchestration

      success
    end
  end
end
