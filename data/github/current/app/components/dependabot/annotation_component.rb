# typed: true
# frozen_string_literal: true

class Dependabot::AnnotationComponent < ApplicationComponent
  include ::TextHelper

  extend T::Sig

  renders_one :disclaimer

  attr_reader :alert_number, :inline, :repository, :warning_level, :tool_name, :alert_title, :alert_message, :annotation_id, :pull_request_review_thread

  def initialize(inline: false, dependabot_annotation_result: nil, annotation_id: 0, fallback_warning_level:, fallback_tool_name:, fallback_alert_title:, fallback_alert_message:, alert_number:, repository:, refs: nil, pull_request: nil, pull_request_review_thread: nil)
    @inline = inline
    @dependabot_annotation_result = dependabot_annotation_result
    @annotation_id = annotation_id
    @repository = repository
    @alert_number = alert_number
    @refs = refs
    @pull_request = pull_request
    @pull_request_review_thread = pull_request_review_thread

    @warning_level = if @dependabot_annotation_result.present?
      # TODO: Implement annotation_level_for_dependabot_annotation and replace annotation_level_for_code_scanning_annotation with it
      CheckAnnotation.annotation_level_for_code_scanning_annotation(@dependabot_annotation_result.result.security_severity, @dependabot_annotation_result.result.rule_severity)
    else
      fallback_warning_level.presence || CheckAnnotation.annotation_level_for_code_scanning_annotation(nil, nil)
    end

    @tool_name = if @code_scanning_annotation_result.present?
      @code_scanning_annotation_result.result&.tool&.name
    else
      fallback_tool_name
    end

    @alert_title = if @dependabot_annotation_result.present?
      strip_tags_and_collapse_whitespace(GitHub::Goomba::MarkdownPipeline.to_html(@dependabot_annotation_result.result&.message_text))
    else
      fallback_alert_title.presence || fallback_alert_message
    end

    @alert_message = "The method _.pluck has been removed from the lodash library in version 4.17.21."
  end

  def div_if_inline(**attrs, &block)
    return tag.div(**attrs, &block) if @inline
    capture(&block)
  end

  def show_alert_severity?
    @dependabot_annotation_result.present?
  end

  def rule_severity
    @dependabot_annotation_result.result&.rule_severity
  end

  def security_severity
    @dependabot_annotation_result.result&.security_severity
  end

  def show_experimental_query_info?
    return false unless @dependabot_annotation_result.present?
    @dependabot_annotation_result.result&.rule&.tags&.include?("experimental") &&
    @dependabot_annotation_result.result&.tool&.name == "Dependabot"

    # @dependabot_annotation_result.result&.rule&.tags&.include?("experimental") &&
    # CodeScanning::Tool.canonical_name(@dependabot_annotation_result.result&.tool&.name) == "Dependabot"
  end

  def result_resolved?
    @dependabot_annotation_result&.result.resolution.present? && @dependabot_annotation_result&.result.resolution != :NO_RESOLUTION
  end

  memoize def alerts_writable_by_current_user?
    false
    # @repository.code_scanning_alerts_writable_by?(current_user)
  end

  memoize def alerts_readable_by_current_user?
    true
    # @repository.code_scanning_alerts_readable_by?(current_user)
  end

  def has_code_paths?
    @dependabot_annotation_result&.has_code_paths || false
  end

  def show_interactive_elements?
    @dependabot_annotation_result.present?
  end

  def ref_names
    # This covers checkruns before August 2020 where the ref was not present, so we need to make sure
    # Turboscan has enough information to identify the alert.
    @refs.presence || @pull_request&.ref_names
  end

  private

  def alert_instance
    @dependabot_annotation_result.result&.most_recent_instance
  end

  sig { returns(T.nilable(T::Array[String])) }
  def base64_ref_names
    return if ref_names.blank?

    ref_names.map { |ref_name| Base64.strict_encode64(ref_name) }
  end
end
