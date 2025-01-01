# typed: true
# frozen_string_literal: true

# Serializer for building webhook payloads for secret scanning alerts. See Hook::Payload::SecretScanningAlertPayload
module Api::Serializer::SecretScanningAlertDependency
  extend T::Helpers
  include GitHub::TokenScanning::SecretScanningHelper
  include SecretScanning::Features::FeatureFlagHelper

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
      secret_type: alert.token&.slug,
      secret_type_display_name: alert.token&.label,
      secret: alert.raw_secret,
      validity: validity_name(alert),
      multi_repo: alert.multi_repo,
      is_base64_encoded: alert.is_base64_encoded,
    }

    hash["publicly_leaked"] = alert.publicly_leaked unless GitHub.single_or_multi_tenant_enterprise?
    hash = hash.merge(resolution_payload(alert, options))
    hash = hash.merge(bypass_payload(alert, options))

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
    hash = {
      number: secret&.number,
      secret_type: secret&.token&.slug,
      secret_type_display_name: secret&.token&.label,
      url: url("/repos/#{nwo}/secret-scanning/alerts/#{secret&.number}"),
      html_url: html_url("/#{nwo}/security/secret-scanning/#{secret&.number}"),
      locations_url: url("/repos/#{nwo}/secret-scanning/alerts/#{secret&.number}/locations"),
      created_at: time(secret&.created_at),
      updated_at: time(secret&.last_modified_at),
      validity: validity_name(secret),
    }
    if feature_flag_enabled?(secret&.repository, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS) ||
      feature_flag_enabled?(secret&.repository&.owner, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS)
      hash[:publicly_leaked] = secret&.publicly_leaked
      hash[:multi_repo] = secret&.multi_repo
    end

    hash = hash.merge(resolution_payload(secret, options))
    hash = hash.merge(bypass_payload(secret, options))

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

    {
      incremental_scans: data[:incremental_scans].map { |scan| secret_scanning_scan_hash(scan) },
      backfill_scans: data[:backfill_scans].map { |scan| secret_scanning_scan_hash(scan) },
      custom_pattern_backfill_scans:,
      pattern_update_scans: data[:pattern_updates].map { |scan| secret_scanning_scan_hash(scan) },
    }
  end

  def secret_scanning_scan_hash(scan_event)
    status = case scan_event.scan.scan_status
    when :SCAN_STATUS_QUEUED, :SCAN_STATUS_PENDING
      "pending"
    when :SCAN_STATUS_STARTED, :SCAN_STATUS_FAILED, :SCAN_STATUS_PAUSED
      "running"
    when :SCAN_STATUS_COMPLETED
      "completed"
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

    case location&.content_type
    when :REPOSITORY_BLOB
      {
        type: "commit",
        details: {
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
      }
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
      {
        type: "issue_title",
        details: {
          issue_title_url: url("/repos/#{nwo}/issues/#{location.content_number}")
        }
      }
    when :ISSUE_BODY
      {
        type: "issue_body",
        details: {
          issue_body_url: url("/repos/#{nwo}/issues/#{location.content_number}")
        }
      }
    when :ISSUE_COMMENT
      {
        type: "issue_comment",
        details: {
          issue_comment_url: url("/repos/#{nwo}/issues/comments/#{location.content_id}")
        }
      }
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
      {
        type: "pull_request_title",
        details: {
          pull_request_title_url: url("/repos/#{nwo}/pulls/#{location.content_number}")
        }
      }
    when :PULL_REQUEST_BODY
      {
        type: "pull_request_body",
        details: {
          pull_request_body_url: url("/repos/#{nwo}/pulls/#{location.content_number}")
        }
      }
    when :PULL_REQUEST_COMMENT
      {
        type: "pull_request_comment",
        details: {
          pull_request_comment_url: url("/repos/#{nwo}/issues/comments/#{location.content_id}")
        }
      }
    when :PULL_REQUEST_REVIEW, :PULL_REQUEST_TIMELINE_COMMENT # keep both until PULL_REQUEST_TIMELINE_COMMENT is deprecated
      {
        type: "pull_request_review",
        details: {
          pull_request_review_url: url("/repos/#{nwo}/pulls/#{location.content_number}/reviews/#{location.content_id}")
        }
      }
    when :PULL_REQUEST_REVIEW_COMMENT
      {
        type: "pull_request_review_comment",
        details: {
          pull_request_review_comment_url: url("/repos/#{nwo}/pulls/comments/#{location.content_id}")
        }
      }
    end
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

  sig { params(alert: T.nilable(GitHub::TokenScanning::Service::Token)).returns(String) }
  def validity_name(alert)
    validity = alert&.validity
    case validity
    when :TOKEN_VALIDITY_UNKNOWN
      "unknown"
    when :TOKEN_VALIDITY_ACTIVE
      "active"
    when :TOKEN_VALIDITY_INACTIVE, :TOKEN_VALIDITY_REVOKED
      "inactive" # consolidate revoked with inactive
    else
      "unknown" #consolidate unverifiable with unknown
    end
  end
end
