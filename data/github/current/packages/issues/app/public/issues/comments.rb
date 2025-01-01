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
      :get_default_branch_spokes,
      :gitrpc_always_include_request_id,
      :html_pipeline_bad_emoji,
      :hydro_async_sink,
      :insights_enabled_staging,
      :insights_enabled,
      :insights_publish_enabled,
      :instrument_rails_callbacks,
      :interaction_limit_kv_fallback,
      :issue_comments_spam_check,
      :issue_touch_pull_request_after_commit,
      :publish_events_to_notifyd,
      :reserved_domain,
      :resolve_references_cache_spokes_adapter,
      :resolve_references_spokes_ref_loader,
      :secret_scanning_read_public_repo_alerts,
      :secure_user_assets_auth_check,
      :secure_user_assets,
      :spokesd_cache_key,
      :spokesd_filter_routes,
      :spokesd_request_timeout_header_spokes_api,
      :tasklist_block_markdown_at_rest,
      :tasklist_block_nested_html_pipeline,
      :tasklist_block_precache,
      :tasklist_block,
      :token_scanning_scan_all_token_types_public,
      :track_issue_and_pr_references_in_background,
      :update_notification_summary_always_enqueue,
      :update_notification_summary_job_use_single_lock,
      :update_notification_summary_with_locks,
      :user_generated_content_hydro_publisher,
      :disable_mathjax,
      :throttle_expensive_gitrpc_calls, # enables throttling for expensive gitrpc calls
      :project_events_repository_id,
      :private_avatars,
      :via_domain_singleton,
      :async_domain_assoc,
      :active_job_default_to_write_connection,
      :active_job_replica_clusters_only,
      :check_reference_exists,
      :key_links_methods,
      :domain_caching_repositories_key_links_cache_key,
      :domain_id_caching_repositories_repositories_by_id,
      :batch_ability_loader,
      :run_batch_ability_loader_experiment,
      :vexi_preload_comments
    ].freeze, T::Array[Symbol])

    sig { params(comment: IssueComment, body: String, editor: User, performed_via_integration: T.nilable(Integration)).returns(T::Boolean) }
    def update_comment(comment, body, editor, performed_via_integration: nil)
      GitHub.flipper.preload PRELOAD_FEATURES
      if GitHub.flipper[:vexi_preload_comments].enabled?
        FeatureFlag.vexi.preload PRELOAD_FEATURES
      end

      !!comment.update_body(body, editor, performed_via_integration: performed_via_integration)
    end
  end
end
