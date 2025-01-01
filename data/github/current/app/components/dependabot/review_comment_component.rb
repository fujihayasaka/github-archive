# typed: true
# frozen_string_literal: true

class Dependabot::ReviewCommentComponent < ApplicationComponent
  extend T::Sig

  # Define a struct for Dependabot review comment
  DependabotReviewComment = Struct.new(
    :id,
    :warning_level,
    :tool_name,
    :alert_title,
    :alert_message,
    :alert_number
  )

  # Define Structs for SuggestedFixAlert, SuggestedFix, and SuggestedFixFile
  SuggestedFixAlert = Struct.new(
    :alert_number, :state, :state_updated_at, :state_updated_actor_id,
    :created_at, :updated_at, :suggested_fix, :rule_sarif_identifier,
    keyword_init: true
  )

  SuggestedFix = Struct.new(
    :description, :files, :dismissed, :created_at, :updated_at,
    :dependency_metadata, :outdated,
    keyword_init: true
  )

  SuggestedFixFile = Struct.new(
    :file_path, :diff_content, :created_at, :updated_at,
    keyword_init: true
  )

  # def self.preload_review_comments(pull_request:)
  #   pull_request.async_preload_code_scanning_alerts
  #   pull_request.async_preload_code_scanning_suggested_fixes
  #   pull_request.code_scanning_review_comments
  # end

  attr_reader :pull_request_review_comment, :pull_request

  def initialize(pull_request_review_comment:, pull_request:, comment_context: nil)
    @pull_request_review_comment = pull_request_review_comment
    @pull_request = pull_request
  end

  memoize def dependabot_review_comment
    # Using hardcoded values from the method for testing purposes
    DependabotReviewComment.new(
      SecureRandom.random_number(1_000_000), # annotation_id
      "critical",                            # fallback_warning_level
      "dependabot",                          # fallback_tool_name
      "fallback message",                    # fallback_alert_title
      "The method _.pluck has been removed from the lodash library in version 4.17.21. [fallback message]", # fallback_alert_message
      1                                      # alert_number
    )
    # pull_request.code_scanning_review_comment_for_comment(@pull_request_review_comment.id)
  end

  memoize def dependabot_alert
    # Create a new AnnotationResult with hardcoded and provided values
    dependabot_alert = Turboscan::Proto::AnnotationResult.new(
      result: Turboscan::Proto::Result.new(
        message_text: "Breaking change detected",
        rule_severity: :ERROR,
        created_at: Google::Protobuf::Timestamp.new(seconds: 1724510823, nanos: 0), # Placeholder timestamp
        resolution: :NO_RESOLUTION,
        resolver_id: 12345, # Placeholder resolver ID
        resolved_at: nil,
        number: 1, # Provided number
        tool: Turboscan::Proto::ToolDescription.new(
          name: "Dependabot",
          guid: "22222222-3333-4444-5555-666666666666", # Placeholder GUID
          version: "1.0.0", # Placeholder version
          alert_count: 1 # Placeholder alert count
        ),
        message_markdown: "The method _.pluck has been removed from the lodash library in version 4.17.21.",
        guid: "22222222-3333-4444-5555-666666666666", # Placeholder GUID
        security_severity: :NO_SECURITY_SEVERITY,
        most_recent_instance: Turboscan::Proto::AlertInstance.new(
          commit_oid: "abcdef1234567890abcdef1234567890abcdef12", # Placeholder commit OID
          location: Turboscan::Proto::Location.new(
            file_path: "lodash-example/package.json", # Provided file path
            start_line: 12, # Provided start line
            end_line: 12,   # Provided end line
            start_column: 5, # Provided start column
            end_column: 22   # Provided end column
          ),
          is_fixed: false,
          has_file_classification: false,
          analysis_key: Turboscan::Proto::AnalysisKey.new(
            id: 42, # Placeholder analysis key ID
            analysis_key: "foo", # Placeholder analysis key
            tool: "CodeQL", # Placeholder tool
            environment: "{}", # Placeholder environment
            category: "foo-category", # Placeholder category
            commit_oid: "abcdef1234567890abcdef1234567890abcdef12" # Placeholder commit OID
          ),
          classification: [],
          message_text: "The hard-coded value \"user:foobar\" is used as  .", # Placeholder message text
          created_at: Google::Protobuf::Timestamp.new(seconds: 1724510823, nanos: 0), # Placeholder timestamp
          ref_name_bytes: "refs/heads/main", # Placeholder ref name bytes
          is_outdated: false
        ),
        is_fixed: false,
        rule: Turboscan::Proto::Rule.new(
          sarif_identifier: "auto-generated-rule-kghw3ywi", # Provided SARIF identifier
          short_description: "Hard-coded credentials", # Placeholder short description
          tags: ["external/cwe/cwe-259", "external/cwe/cwe-321", "external/cwe/cwe-798", "security"], # Placeholder tags
          name: "auto-generated-rule-kghw3ywi", # Placeholder rule name
          severity: :WARNING, # Provided severity
          full_description: "This is a description of the hardcoded test alert.", # Placeholder full description
          help: "# Hardcoded Test Alert\nThis is a test alert to demonstrate hardcoded values in the result object.", # Placeholder help text
          query_uri: "https://example.com/test/query", # Placeholder query URI
          help_uri: "https://example.com/test/help" # Placeholder help URI
        ),
        fixed_at: nil,
        updated_at: Google::Protobuf::Timestamp.new(seconds: 1724510823, nanos: 0), # Placeholder timestamp
        resolution_note: "This is a hardcoded resolution note." # Placeholder resolution note
      ),
      related_locations: [
        Turboscan::Proto::RelatedLocation.new(
          id: 1, # Placeholder ID
          created_at: Google::Protobuf::Timestamp.new(seconds: 1724510823, nanos: 0), # Placeholder timestamp
          updated_at: Google::Protobuf::Timestamp.new(seconds: 1724510823, nanos: 0), # Placeholder timestamp
          message: "This is a hardcoded related location message.", # Placeholder message
          replacement_index: 1, # Placeholder replacement index
          physical_alert_id: 2, # Placeholder physical alert ID
          location: Turboscan::Proto::Location.new(
            file_path: "lodash-example/package.json", # Provided file path
            start_line: 12, # Provided start line
            end_line: 12,   # Provided end line
            start_column: 5, # Provided start column
            end_column: 22   # Provided end column
          )
        )
      ],
      has_code_paths: false # Provided value
    )

    # pull_request.code_scanning_alert_for_review_comment(@pull_request_review_comment)
  end

  memoize def pull_request_refs
    nil
    # pull_request.code_scanning_latest_check_suite&.refs
  end

  memoize def commit_suggestion_modal_id
    "commit-suggested-fix-modal-openai4o"
    # "commit-suggested-fix-modal-#{pull_request_review_comment.id}"
  end

  memoize def author
    pull_request_review_comment.async_user.then do |user|
      next User.ghost if user.nil? || user.hide_from_user?(current_user)

      user
    end.sync
  end

  memoize def thread
    pull_request_review_comment.pull_request_review_thread
  end

  memoize def repository
    pull_request&.repository || current_repository
  end

  memoize def current_head_oid
    with_database_error_fallback do
      pull_request.current_head_oid
    end
  end

  memoize def suggested_fix_alert
    dependabot_suggested_fix_alerts(1)
    # pull_request.code_scanning_suggested_fix_alert(dependabot_review_comment.alert_number)
  end

  def dependabot_suggested_fix_alerts(alert_number)
    return nil unless alert_number.present?

    async_dependabot_suggested_fixes.sync.suggested_fix_alerts&.[](alert_number)
  end

  def async_dependabot_suggested_fixes
    Promise.resolve(get_hardcoded_value_for_test)
  end

  def get_hardcoded_value_for_test
    # Create hardcoded suggested fix file data
    suggested_fix_file = Turboscan::Proto::SuggestedFixFile.new(
      file_path: "lodash-example/src/main-test.js",
      diff_content: "diff --git a/lodash-example/src/main-test.js b/lodash-example/src/main-test.js\n--- a/lodash-example/src/main-test.js\n+++ b/lodash-example/src/main-test.js\n@@ -1,7 +1,7 @@\n const _ = require('lodash');\n \n function getNames(users) {\n-  return _.pluck(users, 'user');\n+  return _.map(users, 'user');\n }\n \n // Test function\n",
      created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
      updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i)
    )

    # Create hardcoded suggested fix data
    suggested_fix = Turboscan::Proto::SuggestedFix.new(
      description: "The breaking change detected by Dependabot is due to the use of the _.pluck method from the lodash library, which was removed in version 4.17.21. To fix this issue, we need to replace the _.pluck method with an equivalent method that is still supported in the latest version of lodash. The _.map method can be used as a replacement for _.pluck.\n\nHere are the steps to fix the problem:\n\nReplace the _.pluck method with _.map in the getNames function in npm-renamed-method/src/main.test.js.\nEnsure that the _.map method is used correctly to achieve the same functionality as _.pluck.",
      files: [suggested_fix_file],
      dismissed: false,
      created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
      updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
      dependency_metadata: [],
      outdated: false
    )

    # Create hardcoded suggested fix alert data
    suggested_fix_alert = Turboscan::Proto::SuggestedFixAlert.new(
      alert_number: 1,
      state: :SUGGESTED_FIX_ALERT_STATE_VALID,
      state_updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
      state_updated_actor_id: 0,
      created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
      updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
      suggested_fix: suggested_fix,
      rule_sarif_identifier: "auto-generated-rule-kghw3ywi"
    )

    # Create the final mocked response object with one alert
    Turboscan::Proto::GetSuggestedFixResponse.new(
      suggested_fix_alerts: {
        1 => suggested_fix_alert
      }
    )
  end

  def empty_suggested_fix_response
    Turboscan::Proto::GetSuggestedFixResponse.new
  end

  def suggested_fix_alert?
    suggested_fix_alert.present?
  end

  def suggested_fix_alert_pending?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_PENDING
  end

  def suggested_fix_alert_error?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_ERROR
  end

  memoize def suggested_fix
    suggested_fix_alert&.suggested_fix
  end

  memoize def show_suggested_fix?
    return false unless suggested_fix? # Don't show the suggested fix if there isn't one
    return false if invalid_suggested_fix? # Don't show the suggested fix if it is invalid

    true
  end

  memoize def show_suggested_fix_actions?
    false
    #return false if dismissed_suggested_fix?
    #return false if applied_suggested_fix?
    #return false if outdated_suggested_fix?
    #return false if code_scanning_alert_resolved?

    #pull_request.can_apply_code_scanning_suggested_fix?(current_user)
  end

  def hide_suggested_fix_summary?
    !collapse_suggested_fix? # Only show the summary if the suggested fix is collapsed
  end

  def collapse_suggested_fix?
    dismissed_suggested_fix? || applied_suggested_fix?
  end

  def collapsed_suggested_fix_message
    if dismissed_suggested_fix?
      "This autofix suggestion was marked as dismissed."
    elsif applied_suggested_fix?
      "This autofix suggestion was applied."
    end
  end

  memoize def show_suggested_fix_actioned_message?
    return true if dismissed_suggested_fix?
    return true if applied_suggested_fix?

    false
  end

  memoize def suggested_fix_actioned_message
    if dismissed_suggested_fix?
      "dismissed this autofix suggestion"
    elsif applied_suggested_fix?
      "commited this autofix suggestion"
    end
  end

  sig { returns(T.nilable(String)) }
  memoize def suggested_fix_actioned_by_unknown_user_message
    if dismissed_suggested_fix?
      "This autofix suggestion was dismissed"
    elsif applied_suggested_fix?
      "This autofix suggestion was applied"
    end
  end

  memoize def suggested_fix_description
    GitHub::Goomba::MarkdownPipeline.to_html(suggested_fix&.description)
  end

  memoize def suggested_fix_diff_entries
    suggested_fix.files.each_with_object([]) do |file, out|
      parser = GitHub::Diff::Parser.new(file.diff_content)
      parser.each { |entry| out << entry }
    end
  rescue GitHub::Diff::Parser::UnrecognizedText => err
    # report the error to Sentry
    Failbot.report!(err)
    []
  end

  memoize def suggested_fix_file_highlighting
    suggested_fix_diff_entries.each_with_object({}) do |diff_entry, out|
      out[diff_entry.path] = DiffEntryHighlighting.new(diff_entry).highlight_lines
    end
  end

  def suggested_fix_dependency_metadata?
    suggested_fix_dependency_metadata.any?
  end

  def suggested_fix_dependency_metadata
    suggested_fix&.dependency_metadata
  end

  def annotation_wrapper(&block)
    yield
    nil # Returning `yield` causes a double render
  end

  def suggested_fix?
    suggested_fix.present? && suggested_fix_diff_entries.any?
  end

  memoize def dismissed_suggested_fix?
    return false unless suggested_fix?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_DISMISSED
  end

  memoize def applied_suggested_fix?
    return false unless suggested_fix?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_APPLIED
  end

  def invalid_suggested_fix?
    return false unless suggested_fix_alert?
    suggested_fix_alert.state == :SUGGESTED_FIX_ALERT_STATE_INVALID
  end

  def outdated_suggested_fix?
    return false unless suggested_fix?
    suggested_fix.outdated
  end

  sig { returns(T.nilable(User)) }
  memoize def state_updated_by
    if suggested_fix_alert&.state_updated_actor_id&.nonzero?
      user = User.find_by(id: suggested_fix_alert.state_updated_actor_id)
      if user.nil?
        user = User.ghost
      elsif user.hide_from_user?(current_user)
        # if the actor is hidden from the current user, treat it as if we have no actor
        user = nil
      end
    else
      user = nil
    end

    user
  end

  def state_updated_at
    suggested_fix_alert&.state_updated_at
  end

  def can_have_suggested_fix?
    return false unless CodeScanning::Autofix.enabled_for_repo?(repository)

    tool_name = if dependabot_alert.present?
      dependabot_alert.result&.tool&.name
    else
      dependabot_review_comment.tool_name
    end

    return false unless CodeScanning::Autofix.generate_for_tool?(repository, tool_name)

    true
  end

  def pending_suggested_fix_with_timeout_wrapper(&block)

    wait_until = pull_request_review_comment.created_at + 10.minutes
    delay = wait_until - Time.zone.now

    content_tag(
      "timeout-content",
      {
        class: "review-comment border-top",
        "data-delay-ms": delay.in_milliseconds.ceil,
      }.merge(test_selector_data_hash("ai-suggested-fix-pending")),
      &block
    ) if delay > 0
  end

  def autofix_suggestion_commit_title
    "Apply Dependabot fix for #{dependabot_review_comment.alert_title.downcase}" if dependabot_review_comment.alert_title.present?
  end

  def autofix_edit_cli_title
    "Edit with GitHub CLI"
  end

  def alive_attrs
    return {} unless CodeScanning::Autofix.enabled_for_repo?(repository)

    {
      class: "js-socket-channel js-updatable-content",
      data: {
        channel: live_update_view_channel(GitHub::WebSocket::Channels.pull_request(pull_request)),
        url: data_url,
        gid: pull_request.global_relay_id,
      }
    }
  end

  def data_url
    pull_request_code_scanning_auto_fix_review_comment_partial_path(
      repository.owner,
      repository,
      pull_request,
      dependabot_review_comment.alert_number,
      comment_id: pull_request_review_comment.id
    )
  end

  # Duplicates functionality from CodeScanning::AnnotationComponent#result_resolved?
  def code_scanning_alert_resolved?
    resolution = dependabot_review_comment&.result&.resolution
    resolution.present? && resolution != :NO_RESOLUTION
  end

  def suggested_fix_show_not_supported?
    suggested_fix_language_unsupported? || suggested_fix_rule_unsupported?
  end

  def suggested_fix_not_supported
    if suggested_fix_language_unsupported?
      prefix = suggested_fix_rule_name.split("/").first.to_sym
      DependabotHelper::AUTOFIX_RULES_LANGUAGE_MAP.fetch(prefix, "Language")
    else
      "Rule #{suggested_fix_rule_name}"
    end
  end

  def suggested_fix_autofix_docs_url
    DocsUrlConfig.url_for("about-autofix")
  end

  private

  def suggested_fix_rule_name
    suggested_fix_alert.rule_sarif_identifier
  end

  def suggested_fix_language_unsupported?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_LANGUAGE_NOT_SUPPORTED
  end

  def suggested_fix_rule_unsupported?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
  end
end
