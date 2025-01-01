# typed: true
# frozen_string_literal: true

class Copilot::SummarizeBannerComponent < ApplicationComponent
  # Keep in sync with the `github.copilot.v2.CopilotSummarizeCopyClick.ContentType`
  # hydro enum:
  CONTENT_TYPES = %w(UNKNOWN ISSUE DISCUSSION).freeze
  DEFAULT_CONTENT_TYPE = "UNKNOWN"

  # summary_path - URL to the endpoint that will summarize content using Copilot; URL should be specific to the
  #                content to be summarized, e.g., include repository and issue/discussion identifiers
  # description - descriptive text to be shown in the banner to tell the user what the Summarize button does
  # repository - the repository that contains the content to be summarized
  # negative_feedback_labels - a hash of options for users to provide negative feedback about the summary that was
  #                            generated; the values should correspond to values in a Hydro enum (e.g., "UNHELPFUL")
  #                            and the keys should be the corresponding human-readable description
  #                            (e.g., "Not helpful")
  # feedback_path - URL to the endpoint that will emit a Hydro event with user-provided feedback
  # feedback_discussion_url - optional URL to a discussion on GitHub where we're collecting feedback about the Copilot
  #                           summaries feature; no link will be shown if this is omitted
  # content_type - the type of content that will be summarized when the `summary_path` endpoint is hit; used for
  #                Hydro analytics
  # websocket_channel - optional websocket channel to be subscribed to in order to render notifications about content
  #                     updates, in case the user wants to regenerate the summary
  # test_selector - how the banner is identified for tests
  # reference_name - Copilot chat reference type for the content being summarized, used when opening chat for
  #                  follow-up conversation about the summary and the summarized content
  sig do
    params(
      summary_path: String,
      description: String,
      repository: Repository,
      feedback_path: String,
      negative_feedback_labels: T::Hash[String, String],
      feedback_discussion_url: T.nilable(String),
      content_type: T.any(String, Symbol),
      websocket_channel: T.nilable(String),
      test_selector: String,
      reference_name: String,
    ).void
  end
  def initialize(summary_path:, description:, repository:, feedback_path:, negative_feedback_labels: {}, feedback_discussion_url: nil, content_type: DEFAULT_CONTENT_TYPE, websocket_channel: nil, test_selector: "copilot-summary", reference_name: "summary")
    @summary_path = summary_path
    @description = description
    @repository = repository
    @websocket_channel = websocket_channel
    @negative_feedback_labels = negative_feedback_labels
    @feedback_path = feedback_path
    @feedback_discussion_url = feedback_discussion_url
    @test_selector = test_selector
    @content_type = fetch_or_fallback(CONTENT_TYPES, content_type.to_s.upcase, DEFAULT_CONTENT_TYPE)
    @reference_name = reference_name
  end

  class NegativeFeedbackForm < ApplicationForm
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

  sig { returns String }
  attr_reader :summary_path, :description, :content_type

  sig { returns T.nilable(String) }
  attr_reader :feedback_discussion_url, :websocket_channel

  sig { returns T::Hash[String, String] }
  attr_reader :negative_feedback_labels

  sig { returns Repository }
  attr_reader :repository

  sig { returns String }
  attr_reader :feedback_path, :reference_name

  sig { returns Integer }
  attr_reader :body_length

  sig { returns T::Boolean }
  def show_feedback_discussion_link?
    return false if GitHub.enterprise?
    return false if feedback_discussion_url.blank?
    user_feature_enabled?(:copilot_summary_beta) || helpers.staff_viewer?
  end

  sig { returns T::Boolean }
  def show_badge?
    return false if GitHub.enterprise?
    return false if user_feature_enabled?(:copilot_summary_ga)
    true
  end

  sig { returns String }
  def badge_content
    if helpers.staff_viewer? && !user_feature_enabled?(:copilot_summary_beta)
      "Staff"
    else
      "Preview"
    end
  end

  sig { returns Symbol }
  def badge_scheme
    if helpers.staff_viewer? && !user_feature_enabled?(:copilot_summary_beta)
      :accent
    else
      :success
    end
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
  memoize def common_hydro_payload_attributes
    payload = {
      repository_id: repository.id,
      organization_id: repository.organization_id,
      content_type: content_type,
      analytics_tracking_id: current_user&.analytics_tracking_id,
    }
  end

  # https://github.com/github/hydro-schemas/blob/07d1ee648890178c33a90e063723674ddb64a326/proto/hydro/schemas/github/copilot/v2/copilot_summarize_copy_click.proto
  sig { returns T::Hash[String, T.untyped] }
  def clipboard_copy_hydro_attributes
    hydro_click_tracking_attributes("copilot_summarize_copy.click", common_hydro_payload_attributes)
  end

  # https://github.com/github/hydro-schemas/blob/07d1ee648890178c33a90e063723674ddb64a326/proto/hydro/schemas/github/copilot/v2/copilot_regenerate_summary_click.proto
  sig { returns T::Hash[String, T.untyped] }
  def regenerate_hydro_attributes
    hydro_click_tracking_attributes("copilot_regenerate_summary.click", common_hydro_payload_attributes)
  end

  # https://github.com/github/hydro-schemas/blob/07d1ee648890178c33a90e063723674ddb64a326/proto/hydro/schemas/github/copilot/v2/copilot_expand_summary_toggle.proto
  sig { returns T::Hash[String, T.untyped] }
  def expand_toggle_hydro_attributes
    hydro_click_tracking_attributes("copilot_expand_summary_toggle.click", common_hydro_payload_attributes.merge(
      { toggle_event: "EXPAND" })
    )
  end

  # https://github.com/github/hydro-schemas/blob/07d1ee648890178c33a90e063723674ddb64a326/proto/hydro/schemas/github/copilot/v2/copilot_expand_summary_toggle.proto
  sig { returns T::Hash[String, T.untyped] }
  def collapse_toggle_hydro_attributes
    hydro_click_tracking_attributes("copilot_expand_summary_toggle.click", common_hydro_payload_attributes.merge(
      { toggle_event: "COLLAPSE" })
    )
  end
end
