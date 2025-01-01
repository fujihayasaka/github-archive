# typed: true
# frozen_string_literal: true

class CodeScanning::AnnotationComponent < ApplicationComponent
  include ::TextHelper
  include CodeScanningHelper

  renders_one :disclaimer

  attr_reader :alert_number, :inline, :repository, :warning_level, :tool_name, :alert_title, :alert_message, :annotation_id, :pull_request_review_thread, :has_pending_dismissal_request, :pending_dismissal_requester, :pending_dismissal_resolution, :pending_dismissal_requested_at

  def initialize(
    inline: false,
    code_scanning_annotation_result: nil,
    annotation_id: 0,
    fallback_warning_level:,
    fallback_tool_name:,
    fallback_alert_title:,
    fallback_alert_message:,
    alert_number:,
    repository:,
    refs: nil,
    pull_request: nil,
    pull_request_review_thread: nil,
    skip_interactive_elements: false,
    has_pending_dismissal_request: false,
    has_rejected_request: false,
    pending_dismissal_requester: nil,
    pending_dismissal_resolution: nil,
    pending_dismissal_requested_at: nil
  )
    @inline = inline
    @code_scanning_annotation_result = code_scanning_annotation_result
    @annotation_id = annotation_id
    @repository = repository
    @alert_number = alert_number
    @refs = refs
    @pull_request = pull_request
    @pull_request_review_thread = pull_request_review_thread
    @skip_interactive_elements = skip_interactive_elements
    @has_pending_dismissal_request = has_pending_dismissal_request
    @has_rejected_request = has_rejected_request
    @pending_dismissal_requester = pending_dismissal_requester
    @pending_dismissal_resolution = pending_dismissal_resolution
    @pending_dismissal_requested_at = pending_dismissal_requested_at

    @warning_level = if @code_scanning_annotation_result.present?
      CheckAnnotation.annotation_level_for_code_scanning_annotation(@code_scanning_annotation_result.result.security_severity, @code_scanning_annotation_result.result.rule_severity)
    else
      fallback_warning_level.presence || CheckAnnotation.annotation_level_for_code_scanning_annotation(nil, nil)
    end

    @tool_name = if @code_scanning_annotation_result.present?
      @code_scanning_annotation_result.result&.tool&.name
    else
      fallback_tool_name
    end

    @alert_title = if @code_scanning_annotation_result.present?
      @code_scanning_annotation_result.result.rule&.short_description.presence ||
      strip_tags_and_collapse_whitespace(GitHub::Goomba::MarkdownPipeline.to_html(@code_scanning_annotation_result.result&.message_text))
    else
      fallback_alert_title.presence || fallback_alert_message
    end

    @alert_message = if @code_scanning_annotation_result.present?
      context = {
        related_locations: @code_scanning_annotation_result.related_locations || [],
        entity: @repository,
        commit_oid: alert_instance&.commit_oid,
      }
      if @code_scanning_annotation_result.result&.message_markdown.present?
        GitHub::Goomba::CodeScanningMarkdownPipeline.to_html(@code_scanning_annotation_result.result&.message_markdown, context, nil)
      else
        GitHub::Goomba::CodeScanningMessagePipeline.to_html(@code_scanning_annotation_result.result&.message_text, context, nil)
      end
    else
      fallback_alert_message
    end
  end

  def div_if_inline(**attrs, &block)
    return tag.div(**attrs, &block) if @inline
    capture(&block)
  end

  def show_alert_severity?
    @code_scanning_annotation_result.present?
  end

  def rule_severity
    @code_scanning_annotation_result&.result.rule_severity
  end

  def security_severity
    @code_scanning_annotation_result&.result.security_severity
  end

  def show_experimental_query_info?
    return false unless @code_scanning_annotation_result.present?
    @code_scanning_annotation_result.result&.rule&.tags&.include?("experimental") &&
    CodeScanning::Tool.canonical_name(@code_scanning_annotation_result.result&.tool&.name) == "CodeQL"
  end

  def result_resolved?
    @code_scanning_annotation_result&.result.resolution.present? && @code_scanning_annotation_result&.result.resolution != :NO_RESOLUTION
  end

  def require_dismissal_comment?
    CodeScanning::AlertDismissalService.new(@repository).enabled?
  end

  memoize def alerts_writable_by_current_user?
    @repository.code_scanning_alerts_writable_by?(current_user)
  end

  memoize def alerts_readable_by_current_user?
    @repository.code_scanning_alerts_readable_by?(current_user)
  end

  def has_code_paths?
    @code_scanning_annotation_result&.has_code_paths || false
  end

  def show_interactive_elements?
    return false if @skip_interactive_elements
    @code_scanning_annotation_result.present?
  end

  sig { returns(T.nilable(T::Boolean)) }
  def show_as_code_quality_annotation?
    @pull_request&.code_scanning_code_quality?(@code_scanning_annotation_result)
  end

  sig { returns(String) }
  def dismiss_button_title
    if show_as_code_quality_annotation?
      "Dismiss finding"
    else
      "Dismiss alert"
    end
  end

  def show_as_copilot_code_review?
    @pull_request&.code_scanning_copilot_code_review?(@code_scanning_annotation_result)
  end

  def ref_names
    # This covers checkruns before August 2020 where the ref was not present, so we need to make sure
    # Turboscan has enough information to identify the alert.
    @refs.presence || @pull_request&.ref_names
  end

  def alert_classifications
    @code_scanning_annotation_result&.result&.most_recent_instance&.classification || []
  end

  def show_reopen_alert_button?
    alerts_writable_by_current_user? && result_resolved?
  end

  def show_dismiss_alert_button?
    return false unless alerts_writable_by_current_user?
    return false if result_resolved?

    true
  end

  def delegated_alert_dismissal_enabled?
    CodeScanning::AlertDismissalService.new(repository).enabled?
  end

  def dismiss_alert_button_label
    return "Submit request" if delegated_alert_dismissal_enabled?

    if show_as_code_quality_annotation?
      "Dismiss finding"
    else
      "Dismiss alert"
    end
  end

  def dismiss_reasons_menu_singular
    if show_as_code_quality_annotation?
      {
        WONT_FIX: "This finding is not relevant",
        FALSE_POSITIVE: "This finding is not valid",
        USED_IN_TESTS: "This finding is not in production code",
      }
    else
      {
        WONT_FIX: "This alert is not relevant",
        FALSE_POSITIVE: "This alert is not valid",
        USED_IN_TESTS: "This alert is not in production code",
      }
    end
  end

  def dismiss_reasons_menu_plural
    if show_as_code_quality_annotation?
      {
        WONT_FIX: "These findings are not relevant",
        FALSE_POSITIVE: "These findings are not valid",
        USED_IN_TESTS: "These findings are not in production code",
      }
    else
      {
        WONT_FIX: "These alerts are not relevant",
        FALSE_POSITIVE: "These alerts are not valid",
        USED_IN_TESTS: "These alerts are not in production code",
      }
    end
  end

  def dismiss_alert_path
    return urls.repository_code_scanning_dismissal_request_create_path(repository.owner, repository) if delegated_alert_dismissal_enabled?

    urls.repository_code_scanning_close_path(repository.owner, repository)
  end

  sig { returns(String) }
  def annotation_title
    title = content_tag(:span, class: "mx-1 text-bold") do
      if show_as_code_quality_annotation?
        "Code quality"
      elsif show_as_copilot_code_review?
        "Copilot Code Review"
      else
        "Code scanning"
      end
    end

    title = safe_join([title, " / #{tool_name}"]) if tool_name.present?
    title
  end

  private

  def alert_instance
    @code_scanning_annotation_result&.result&.most_recent_instance
  end

  sig { returns(T.nilable(T::Array[String])) }
  def base64_ref_names
    return if ref_names.blank?

    ref_names.map { |ref_name| Base64.strict_encode64(ref_name) }
  end
end
