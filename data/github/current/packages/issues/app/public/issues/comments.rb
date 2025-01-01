# typed: strict
# frozen_string_literal: true

module Issues
  module Comments
    extend self
    extend T::Sig

    PRELOAD_FEATURES = T.let([
      :active_job_skip_enqueue,
      :adaptive_card_markdown_parsing,
      :add_oauth_app_to_dog_tags,
      :aqueduct_enqueue_to_gateway,
      :aqueduct_enqueue_to_secondary,
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
      :notifyd_enable_issues_explicit_auto_subscriptions,
      :notifyd_notifications_worker_jobs,
      :permission_enforcer_with_caching,
      :publish_events_to_notifyd,
      :reserved_domain,
      :secret_scanning_read_public_repo_alerts,
      :secure_user_assets_auth_check,
      :secure_user_assets,
      :spokesd_cache_key,
      :spokesd_filter_routes,
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
      :rpc_mysql_dist_time_metric_extra_tags,
      :project_events_repository_id,
      :active_job_default_to_write_connection,
      :active_job_replica_clusters_only,
      :ability_loader_size_metric
    ].freeze, T::Array[Symbol])

    sig { params(comment: IssueComment, body: String, editor: User, performed_via_integration: T.nilable(Integration)).returns(T::Boolean) }
    def update_comment(comment, body, editor, performed_via_integration: nil)
      GitHub.flipper.preload PRELOAD_FEATURES

      !!comment.update_body(body, editor, performed_via_integration: performed_via_integration)
    end
  end
end
