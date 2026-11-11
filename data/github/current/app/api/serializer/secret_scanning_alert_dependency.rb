# typed: true
# frozen_string_literal: true

# Serializer for building webhook payloads for secret scanning alerts. See Hook::Payload::SecretScanningAlertPayload
module Api::Serializer::SecretScanningAlertDependency
  extend T::Helpers
  include GitHub::TokenScanning::SecretScanningHelper
  include SecretScanning::Features::FeatureFlagHelper
  AlertSerializer = SecretScanning::Util::AlertSerializer

  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def enterprise_secret_scanning_alerts_hash(data, options)
    alerts = data.fetch(:alerts, [])
    return nil unless alerts

    resolvers = resolvers_by_ids(alerts)
    bypassers = bypassers_by_ids(alerts)

    alerts.map do |alert|
      alert.set_resolver(resolvers[alert.resolver_id])
      alert.set_bypasser(bypassers[alert.bypasser_id])
      secret_scanning_alert_hash(alert, options.merge({ repo: alert.repository }))
        .merge({ repository: simple_repository_hash(alert.repository, options) })
    end
  end

  def org_secret_scanning_alerts_hash(data, options)
    alerts = data.fetch(:alerts, [])
    return nil unless alerts

    resolvers = resolvers_by_ids(alerts)
    bypassers = bypassers_by_ids(alerts)

    alerts.map do |alert|
      alert.set_resolver(resolvers[alert.resolver_id])
      alert.set_bypasser(bypassers[alert.bypasser_id])
      secret_scanning_alert_hash(alert, options.merge({ repo: alert.repository }))
        .merge({ repository: simple_repository_hash(alert.repository, options) })
    end
  end

  def secret_scanning_alerts_hash(data, options)
    alerts = data.fetch(:alerts, [])
    return nil unless alerts

    resolvers = resolvers_by_ids(alerts)
    bypassers = bypassers_by_ids(alerts)

    alerts.map do |alert|
      alert.set_resolver(resolvers[alert.resolver_id])
      alert.set_bypasser(bypassers[alert.token&.push_protection_bypassed_by_user_id])
      secret_scanning_alert_hash(alert, options)
    end
  end

  sig do
    params(
      alert: GitHub::TokenScanning::Service::Token,
      options: T.untyped, # Not a hash. This is some weird untyped struct (shows up as `.` in Sorbet error msg).
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def secret_scanning_alert_hash(alert, options)
    repository = options[:repo]

    hash = {
      number: alert.number,
      created_at: time(alert.created_at),
      updated_at: time(alert.last_modified_at),
      url: url("/repos/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/secret-scanning/alerts/#{alert.number}"),
      html_url: html_url("/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/security/secret-scanning/#{alert.number}"),
      locations_url: url("/repos/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/secret-scanning/alerts/#{alert.number}/locations"),
      state: alert.resolved? ? "resolved" : "open",
      secret_type: alert.token.slug,
      secret_type_display_name: alert.token.label,
      provider: alert.token_type_provider,
      provider_slug: alert.token_type_provider.present? ? alert.token_type_provider.downcase.gsub(" ", "_") : nil,
      validity: AlertSerializer.validity_name(alert),
      multi_repo: alert.multi_repo,
      is_base64_encoded: alert.is_base64_encoded,
    }
    if alert.raw_secret.present?
      hash[:secret] = alert.raw_secret
    end

    if alert.first_location
      location_detail = secret_scanning_alert_location_from_object(alert.first_location, repository, options)
      hash[:first_location_detected] = location_detail[:details] if location_detail
    end

    if alert.token.has_more_locations != nil
      hash[:has_more_locations] = alert.token.has_more_locations&.value
    end

    hash["publicly_leaked"] = alert.publicly_leaked unless GitHub.single_or_multi_tenant_enterprise?
    hash = hash.merge(resolution_payload(alert, options))
    hash = hash.merge(bypass_payload(alert, options))
    hash = hash.merge(closure_request_payload(alert, options))
    hash["assigned_to"] = user_hash(alert.assigned_user, options)

    if options[:include_secret_scanning_metadata] && feature_flag_enabled_in_hierarchy?(alert.repository, FeatureFlags::INCLUDE_STORED_METADATA_API)
      md = token_metadata_payload(alert, options)
      hash[:metadata] = md if md
    end

    hash
  end

  # Builds payload for webhooks.
  sig do
    params(
      event: T.any(Hook::Event::SecretScanningAlertEvent, Hook::Event::SecretScanningAlertLocationEvent),
      options: T::Hash[Symbol, T.untyped],
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def secret_scanning_alert_webhook_hash(event, options)
    nwo = event.target_repository.readonly_name_with_owner_for_api(use: options[:serialize_login])
    secret = event.secret
    if secret.nil?
      return {}
    end

    hash = {
      number: secret.number,
      secret_type: secret.token.slug,
      secret_type_display_name: secret.token.label,
      provider: secret.token_type_provider,
      provider_slug: secret.token_type_provider.present? ? secret.token_type_provider.downcase.gsub(" ", "_") : nil,
      url: url("/repos/#{nwo}/secret-scanning/alerts/#{secret.number}"),
      html_url: html_url("/#{nwo}/security/secret-scanning/#{secret.number}"),
      locations_url: url("/repos/#{nwo}/secret-scanning/alerts/#{secret.number}/locations"),
      created_at: time(secret.created_at),
      updated_at: time(secret.last_modified_at),
      validity: AlertSerializer.validity_name(secret),
    }
    if feature_flag_enabled_in_hierarchy?(secret.repository, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS) ||
      feature_flag_enabled_in_hierarchy?(secret.repository.owner, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS)
      hash[:publicly_leaked] = secret.publicly_leaked
      hash[:multi_repo] = secret.multi_repo
    end

    if feature_flag_enabled_in_hierarchy?(secret.repository, FeatureFlags::METADATA_EVENTS_WEBHOOKS)
      md = token_metadata_payload(secret, options)
      hash[:metadata] = md if md
    end

    hash = hash.merge(resolution_payload(secret, options))
    hash = hash.merge(bypass_payload(secret, options))
    hash = hash.merge(closure_request_payload(secret, options))
    hash["assigned_to"] = user_hash(secret.assigned_user, options)

    hash
  end

  # Builds payload for resolution fields, which are nil for open alerts.
  def resolution_payload(alert, options)
    payload = {}

    if alert.reopened?
      payload = {
        resolution: nil,
        resolved_by: nil,
        resolved_at: nil,
        resolution_comment: alert&.token&.resolution_comment&.presence
      }
    else
      payload = {
        resolution: alert.resolution,
        resolved_by: user_hash(alert.resolver, options),
        resolved_at: time(alert.resolved_at),
        resolution_comment: alert&.token&.resolution_comment&.presence
      }
    end
    payload
  end

  sig { params(alert: GitHub::TokenScanning::Service::Token, options: T.untyped).returns(T::Array[{ key: String, value: String }]) }
  def token_metadata_payload(alert, options)
    begin
      metadata = SecretScanning::Models::PartnerTokenMetadata.decrypt_to_pairs(alert.encrypted_metadata)
    rescue => e
      Failbot.report(e)
    end

    return [] if metadata.nil?

    kvps = metadata.map do |item|
      metadata_key = item[:key]
      metadata_hash_key =
      case metadata_key
      when "Owner email"
        "owner_email"
      when "Secret ID"
        "secret_id"
      when "Secret name"
        "secret_name"
      when "Owner ID"
        "owner_id"
      when "Owner name"
        "owner_name"
      when "Org name"
        "org_name"
      when "Org ID"
        "org_id"
      when "Secret issued date"
        "secret_issued_date"
      when "Secret expiry date"
        "secret_expiry_date"
      when "Secret last used date"
        "secret_last_used_date"
      when "Organization access"
        "organization_access"
      else
        nil
      end
      { key: metadata_hash_key, value: item[:value] } if metadata_hash_key
    end

    kvps.compact
  end

  def bypass_payload(alert, options)
    if alert.token&.push_protection_bypassed
      bypass_payload = {
        push_protection_bypassed: true,
        push_protection_bypassed_by: user_hash(alert.bypasser, options),
        push_protection_bypassed_at: time(alert.token.push_protection_bypassed_at)
      }

      bypass_response = Exemptions::ExemptionResponse.find_by(exemption_request: alert.token.bypass_exemption_request_id) if alert.token.bypass_exemption_request_id != 0
      if bypass_response.present?
        bypass_payload[:push_protection_bypass_request_reviewer] = user_hash(bypass_response.reviewer, options)
        bypass_payload[:push_protection_bypass_request_reviewer_comment] = bypass_response.message || ""
        bypass_payload[:push_protection_bypass_request_comment] = bypass_response.exemption_request&.requester_comment || ""
        bypass_payload[:push_protection_bypass_request_html_url] = SecretScanning::BypassDelegation.secret_scanning_bypass_url(T.must(bypass_response.exemption_request))
      else
        bypass_payload[:push_protection_bypass_request_reviewer] = nil
        bypass_payload[:push_protection_bypass_request_reviewer_comment] = nil
        bypass_payload[:push_protection_bypass_request_comment] = nil
        bypass_payload[:push_protection_bypass_request_html_url] = nil
      end

      return bypass_payload
    end

    {
        push_protection_bypassed: false,
        push_protection_bypassed_by: nil,
        push_protection_bypassed_at: nil,
        push_protection_bypass_request_reviewer: nil,
        push_protection_bypass_request_reviewer_comment: nil,
        push_protection_bypass_request_comment: nil,
        push_protection_bypass_request_html_url: nil,
  }
  end

  # Builds payload for delegated closure request fields (requester + reviewer comments).
  # Looks up the ExemptionRequest by resource_identifier (alert number) from the DB
  # rather than using the Token proto's closure_exemption_request_id, which can be
  # stale when multiple closure requests exist for the same alert.
  def closure_request_payload(alert, options)
    repository = options[:repo] || alert.repository
    return {} unless repository && feature_flag_enabled_in_hierarchy?(repository, FeatureFlags::CLOSURE_REQUEST_COMMENT_FIELDS)

    closure_request = Exemptions::ExemptionRequest
      .includes(:latest_response)
      .where(
        request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
        resource_owner: repository,
        resource_identifier: alert.number.to_s,
      )
      .order(created_at: :desc)
      .first

    # Verify the request's eligibility before including the fields in the payload.
    # Eligible requests are those that are either pending or have been approved, but not yet expired.
    if closure_request.present? && !closure_request.expired? && (closure_request.approved? || closure_request.pending?)
      closure_response = closure_request.latest_response
      return {
        closure_request_comment: closure_request.requester_comment,
        closure_request_reviewer_comment: closure_response&.message,
        closure_request_reviewer: closure_response ? user_hash(closure_response.reviewer, options) : nil,
      }
    end

    {
      closure_request_comment: nil,
      closure_request_reviewer_comment: nil,
      closure_request_reviewer: nil,
    }
  end

  # Serializer for alert locations
  def secret_scanning_alert_locations_hash(data, options)
    repository = options[:repo]

    alert = data[:alert]
    locations = alert.included_locations || []

    locations.map do |location|
      secret_scanning_alert_location_from_object(location, repository, options)
    end
  end

  def secret_scanning_alert_location_webhook_hash(event, options)
    secret_scanning_alert_location_from_object(event.location, event.target_repository, options)
  end

  def secret_scanning_scans_history_hash(data, options)
    custom_pattern_backfill_scans = data[:custom_pattern_scans].map do |scan_event|
      owner_scope = case scan_event.custom_pattern.owner_scope
      when :REPOSITORY_SCOPE
        "repository"
      when :ORGANIZATION_SCOPE
        "organization"
      when :BUSINESS_SCOPE
        "enterprise"
      else
        ""
      end

      secret_scanning_scan_hash(scan_event).merge({
        pattern_name: scan_event.custom_pattern.name,
        pattern_scope: owner_scope,
      })
    end

    result = {
      incremental_scans: data[:incremental_scans].map { |scan| secret_scanning_scan_hash(scan) },
      backfill_scans: data[:backfill_scans].map { |scan| secret_scanning_scan_hash(scan) },
      custom_pattern_backfill_scans:,
      pattern_update_scans: data[:pattern_updates].map { |scan| secret_scanning_scan_hash(scan) },
    }

    if data[:generic_secrets_backfill_scans]
      result[:generic_secrets_backfill_scans] = data[:generic_secrets_backfill_scans].map { |scan| secret_scanning_scan_hash(scan) }
    end

    result
  end

  # Maps a TSS scan_status enum onto the public API "status" string.
  #
  # Buckets:
  #   - "pending":   queued/pending
  #   - "running":   started, failed (transient retry), or paused
  #   - "completed": completed, cancelled, parent_job_group_cancelled (terminal-but-not-erroring outcomes)
  #   - "failed":    terminal (retry budget exhausted; permanent failure surfaced for self-diagnosis)
  #
  # When "failed" is emitted we increment a counter so we can quantify how
  # often scan events are surfaced as permanent failures via the public API;
  # consumers can filter by the `scan_type:` tag for specific scan classes.
  def secret_scanning_scan_hash(scan_event)
    status = case scan_event.scan.scan_status
    when :SCAN_STATUS_QUEUED, :SCAN_STATUS_PENDING
      "pending"
    when :SCAN_STATUS_STARTED, :SCAN_STATUS_FAILED, :SCAN_STATUS_PAUSED
      "running"
    when :SCAN_STATUS_COMPLETED, :SCAN_STATUS_CANCELLED, :SCAN_STATUS_PARENT_JOB_GROUP_CANCELLED
      "completed"
    when :SCAN_STATUS_TERMINAL
      GitHub.dogstats.increment(
        "secret_scanning.api.scan_history.failed_status",
        tags: ["source:#{scan_event.source_slug}", "scan_type:#{scan_event.type_slug}"],
      )
      "failed"
    else
      "unknown"
    end

    {
      type: scan_event.source_slug,
      status: status,
      completed_at: scan_event.scan.completed_at&.to_time&.utc&.iso8601,
      started_at: scan_event.scan.started_at&.to_time&.utc&.iso8601
    }
  end

  def secret_scanning_alert_location_from_object(location, repo, options)
    nwo = repo.readonly_name_with_owner_for_api(use: options[:serialize_login])
    include_html_url = feature_flag_enabled_in_hierarchy?(repo, FeatureFlags::LOCATION_HTML_URL)

    case location&.content_type
    when :REPOSITORY_BLOB
      details = {
        path: location.path,
        start_line: location.start_line,
        end_line: location.end_line,
        start_column: location.normalized_start_column,
        end_column: location.normalized_end_column,
        blob_sha: location.blob_oid,
        blob_url: url("/repos/#{nwo}/git/blobs/#{location.blob_oid}"),
        commit_sha: location.commit_oid,
        commit_url: url("/repos/#{nwo}/git/commits/#{location.commit_oid}"),
      }
      if include_html_url
        effective_end_line = location.end_line > 0 ? location.end_line : location.start_line
        line_fragment = location.start_line > 0 ? "#L#{location.start_line}-L#{effective_end_line}" : ""
        details[:html_url] = html_url("/#{nwo}/blob/#{location.commit_oid}/#{location.path}#{line_fragment}")
      end
      { type: "commit", details: details }
    when :WIKI_BLOB
      {
        type: "wiki_commit",
        details: {
          path: location.path,
          start_line: location.start_line,
          end_line: location.end_line,
          start_column: location.normalized_start_column,
          end_column: location.normalized_end_column,
          blob_sha: location.blob_oid,
          page_url: html_url("/#{nwo}/wiki/#{File.basename(location.path, ".*")}/#{location.commit_oid}"),
          commit_sha: location.commit_oid,
          commit_url: html_url("/#{nwo}/wiki/_compare/#{location.commit_oid}"),
        }
      }
    when :ISSUE_TITLE
      location_with_optional_html_url(
        { issue_title_url: url("/repos/#{nwo}/issues/#{location.content_number}") },
        "issue_title",
        html_url("/#{nwo}/issues/#{location.content_number}"),
        include_html_url,
      )
    when :ISSUE_BODY
      location_with_optional_html_url(
        { issue_body_url: url("/repos/#{nwo}/issues/#{location.content_number}") },
        "issue_body",
        html_url("/#{nwo}/issues/#{location.content_number}"),
        include_html_url,
      )
    when :ISSUE_COMMENT
      location_with_optional_html_url(
        { issue_comment_url: url("/repos/#{nwo}/issues/comments/#{location.content_id}") },
        "issue_comment",
        html_url("/#{nwo}/issues/#{location.content_number}#issuecomment-#{location.content_id}"),
        include_html_url,
      )
    when :DISCUSSION_TITLE
      {
        type: "discussion_title",
        details: {
          discussion_title_url: html_url("/#{nwo}/discussions/#{location.content_number}")
        }
      }
    when :DISCUSSION_BODY
      {
        type: "discussion_body",
        details: {
          discussion_body_url: html_url("/#{nwo}/discussions/#{location.content_number}#discussion-#{location.content_id}")
        }
      }
    when :DISCUSSION_COMMENT
      {
        type: "discussion_comment",
        details: {
          discussion_comment_url: html_url("/#{nwo}/discussions/#{location.content_number}##{DiscussionComment.dom_id(location.content_id)}")
        }
      }
    when :PULL_REQUEST_TITLE
      location_with_optional_html_url(
        { pull_request_title_url: url("/repos/#{nwo}/pulls/#{location.content_number}") },
        "pull_request_title",
        html_url("/#{nwo}/pull/#{location.content_number}"),
        include_html_url,
      )
    when :PULL_REQUEST_BODY
      location_with_optional_html_url(
        { pull_request_body_url: url("/repos/#{nwo}/pulls/#{location.content_number}") },
        "pull_request_body",
        html_url("/#{nwo}/pull/#{location.content_number}"),
        include_html_url,
      )
    when :PULL_REQUEST_COMMENT
      location_with_optional_html_url(
        { pull_request_comment_url: url("/repos/#{nwo}/issues/comments/#{location.content_id}") },
        "pull_request_comment",
        html_url("/#{nwo}/pull/#{location.content_number}#issuecomment-#{location.content_id}"),
        include_html_url,
      )
    when :PULL_REQUEST_REVIEW, :PULL_REQUEST_TIMELINE_COMMENT # keep both until PULL_REQUEST_TIMELINE_COMMENT is deprecated
      location_with_optional_html_url(
        { pull_request_review_url: url("/repos/#{nwo}/pulls/#{location.content_number}/reviews/#{location.content_id}") },
        "pull_request_review",
        html_url("/#{nwo}/pull/#{location.content_number}#pullrequestreview-#{location.content_id}"),
        include_html_url,
      )
    when :PULL_REQUEST_REVIEW_COMMENT
      location_with_optional_html_url(
        { pull_request_review_comment_url: url("/repos/#{nwo}/pulls/comments/#{location.content_id}") },
        "pull_request_review_comment",
        html_url("/#{nwo}/pull/#{location.content_number}#discussion_r#{location.content_id}"),
        include_html_url,
      )
    when :ACTION_LOGS
      {
        type: "actions_log",
        details: {
          path: location.path,
          start_line: location.start_line,
          end_line: location.end_line,
          start_column: location.normalized_start_column,
          end_column: location.normalized_end_column,
        }
      }
    end
  end

  def location_with_optional_html_url(details, type, location_html_url, include_html_url)
    details[:html_url] = location_html_url if include_html_url
    { type: type, details: details }
  end

  sig { params(alerts: T::Array[GitHub::TokenScanning::Service::Token]).returns(T::Hash[Integer, User]) }
  def resolvers_by_ids(alerts)
    resolver_ids = alerts.map { |alert| alert.resolver_id }
    resolvers = ActiveRecord::Base.connected_to(role: :reading) { User.where(id: resolver_ids) }
    resolvers.reduce({}) do |acc, u|
      acc[u.id] = u
      acc
    end
  end

  sig { params(alerts: T::Array[GitHub::TokenScanning::Service::Token]).returns(T::Hash[Integer, User]) }
  def bypassers_by_ids(alerts)
    bypasser_ids = alerts.map { |alert| alert.token.push_protection_bypassed_by_user_id }
    bypassers = ActiveRecord::Base.connected_to(role: :reading) { User.where(id: bypasser_ids) }
    bypassers.reduce({}) do |acc, u|
      acc[u.id] = u
      acc
    end
  end
end
