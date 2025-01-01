# typed: true
# frozen_string_literal: true

require "json"

module SecretScanningCustomPatternsHelper
  DRY_RUN_REPO_SELECTOR_DEFAULT_SUGGESTIONS = 15
  DRY_RUN_RESULT_TRUNCATION_LENGTH = 40
  DRY_RUN_CANCEL_FAILED_MESSAGE = "Failed to cancel dry run. Dry run may have already completed or failed. Please try again if dry run is still in progress."
  CUSTOM_PATTERNS_PAGE_SIZE = 10

  sig { params(params: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def self.parse_post_processing(params)
    # Parse post processing rules
    must_match = []
    must_not_match = []
    GitHub.secret_scanning_max_post_processing_expressions_per_pattern.times do |i|
      case params["post_processing_rule_#{i}"]
      when :must_match.to_s
        if params["post_processing_#{i}"].present?
          must_match << params["post_processing_#{i}"]
        end
      when :must_not_match.to_s
        if params["post_processing_#{i}"].present?
          must_not_match << params["post_processing_#{i}"]
        end
      end
    end
    {
      start_delimiter: params[:before_secret],
      end_delimiter: params[:after_secret],
      must_match: must_match,
      must_not_match: must_not_match,
    }
  end

  sig { params(pattern_matches: T::Array[T.untyped], error: T.untyped, has_wildcard_warning: T::Boolean).returns(T.untyped) }
  def self.to_json_pattern_matches(pattern_matches, error, has_wildcard_warning)
    matches_json = pattern_matches.map do |pattern_match|
      { start: pattern_match.start, end: pattern_match.end }
    end.to_json
    if !error.nil?
      return { has_matches: false, error: error.to_h, has_wildcard_warning: has_wildcard_warning }
    end
    { has_matches: pattern_matches.any?, matches: matches_json, has_wildcard_warning: has_wildcard_warning }
  end

  # Parse user's preference for deleting/resolving secrets matched by a pattern, when the pattern is being removed.
  sig { params(post_delete_action: T.nilable(String)).returns(T.nilable(Symbol)) }
  def self.parse_post_delete_action(post_delete_action)
    return nil if post_delete_action.nil?
    if post_delete_action.include? "delete_alerts"
      :DELETE_ALERTS
    else
      :RESOLVE_ALERTS
    end
  end

  # Parse custom pattern from service response
  def self.custom_pattern_from_response(response)
    response&.data&.custom_pattern
  end

  # DRY RUN HELPER METHODS

  sig { params(scan_ids_json: T.nilable(String), owner: T.any(Repository, Organization, Business), owner_scope: Symbol).returns(T.nilable(T::Array[Integer])) }
  def self.parse_scan_ids(scan_ids_json, owner, owner_scope)
    return nil if scan_ids_json.nil?
    begin
      JSON::parse(scan_ids_json)
    rescue JSON::ParserError => exception
      Failbot.report(exception, owner_id: owner, owner_scope: owner_scope)
      nil
    end
  end

  sig { params(dry_run_info: T.nilable(T::Hash[Symbol, Symbol])).returns(Symbol) }
  def self.dry_run_status(dry_run_info)
    return :UNKNOWN if dry_run_info.nil? || dry_run_info[:status] == :UNKNOWN_SCAN_STATUS
    T.must(dry_run_info[:status])
  end

  sig { params(mode: Symbol, status: T.nilable(Symbol)).returns(T::Boolean) }
  def self.allow_dry_run_cancellation?(mode, status)
    return false unless mode == :unpublished || mode == :published
    return true if status == :QUEUED || status == :INPROGRESS
    false
  end

  sig { params(selected_repos_json: T.nilable(String)).returns(T::Array[Integer]) }
  def self.parse_dry_run_selected_repos(selected_repos_json)
    return [] if selected_repos_json.nil?
    begin
      JSON::parse(selected_repos_json)
    rescue JSON::ParserError => exception
      Failbot.report(exception, selected_repos_json: selected_repos_json)
      []
    end
  end

  sig { params(params: T.untyped).returns(T.untyped) }
  def self.get_custom_patterns_cursor(params)
    cursor = nil
    if params[:next_cursor_button_udp]
      cursor = params[:next_cursor]
    elsif params[:previous_cursor_button_udp]
      cursor = params[:previous_cursor]
      cursor
    end
  end

  # Calculates count of scan statuses from a list of scan status objects
  sig { params(scan_status_entries: T::Array[GitHub::Proto::SecretScanning::Api::V1::DryRunScanStatusCount]).returns(Integer) }
  def self.dry_runs_v2_scan_status_count(scan_status_entries)
    return 0 if scan_status_entries.empty?
    scan_status_entries.map { |scan_status_entry| scan_status_entry.count }.inject(0, :+)
  end
end
