# typed: true
# frozen_string_literal: true

class Copilot::SummarizeBannerComponent < ApplicationComponent
  extend T::Sig

  # Keep in sync with the `github.copilot.v2.CopilotSummarizeCopyClick.ContentType`
  # hydro enum:
  CONTENT_TYPES = %w(UNKNOWN ISSUE DISCUSSION).freeze
  DEFAULT_CONTENT_TYPE = "UNKNOWN"

  sig do
    params(
      summary_path: String,
      description: String,
      repository: Repository,
      negative_feedback_labels: T::Hash[String, String],
      feedback_path: T.nilable(String),
      feedback_discussion_url: T.nilable(String),
      content_type: T.any(String, Symbol),
      websocket_channel: T.nilable(String),
      test_selector: String
    ).void
  end
  def initialize(summary_path:, description:, repository:, negative_feedback_labels: {}, feedback_path: nil, feedback_discussion_url: nil, content_type: DEFAULT_CONTENT_TYPE, websocket_channel: nil, test_selector: "copilot-summary")
    @summary_path = summary_path
    @description = description
    @repository = repository
    @websocket_channel = websocket_channel
    @negative_feedback_labels = negative_feedback_labels
    @feedback_path = feedback_path
    @feedback_discussion_url = feedback_discussion_url
    @test_selector = test_selector
    @content_type = fetch_or_fallback(CONTENT_TYPES, content_type.to_s.upcase, DEFAULT_CONTENT_TYPE)
  end

  class NegativeFeedbackForm < ApplicationForm
    extend T::Sig

    form do |f|
      if @negative_feedback_labels.present?
        f.check_box_group(label: "This summary is...", name: "feedback_choices") do |group|
          @negative_feedback_labels.each do |value, label|
            group.check_box(label: label, value: value)
          end
        end
      end
      if @show_freeform_text_field
        f.text_area(
          name: "feedback_text",
          label: "How could we improve this summary?",
          rows: 7,
        )
      end
      f.submit(label: "Submit feedback", name: "", scheme: :primary)
    end

    def initialize(negative_feedback_labels:, show_freeform_text_field:)
      @negative_feedback_labels = negative_feedback_labels
      @show_freeform_text_field = show_freeform_text_field
    end
  end

  private

  sig { returns T::Boolean }
  def render?
    return false unless logged_in?
    T.must(current_copilot_user).has_copilot_enterprise_access?
  end

  sig { returns String }
  attr_reader :summary_path, :description, :content_type

  sig { returns T.nilable(String) }
  attr_reader :feedback_path, :feedback_discussion_url, :websocket_channel

  sig { returns T::Hash[String, String] }
  attr_reader :negative_feedback_labels

  sig { returns Repository }
  attr_reader :repository

  sig { returns T::Boolean }
  def show_feedback_discussion_link?
    return false if GitHub.enterprise?
    return false if feedback_discussion_url.blank?
    current_user.site_admin? || current_user.employee?
  end

  sig { returns T::Boolean }
  def user_feedback_opt_in_enabled?
    org = repository.organization
    if org
      Copilot::Organization.new(org).user_feedback_opt_in_enabled?
    else
      T.must(current_copilot_user).user_feedback_opt_in_enabled?
    end
  end

  sig { returns String }
  memoize def current_time_iso8601
    Time.current.iso8601
  end

  sig { returns T::Hash[String, T.untyped] }
  memoize def clipboard_copy_hydro_attributes
    payload = {
      repository_id: repository.id,
      organization_id: repository.organization_id,
      content_type: content_type,
    }
    hydro_click_tracking_attributes("copilot_summarize_copy.click", payload)
  end
end
