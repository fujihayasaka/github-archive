# typed: true
# frozen_string_literal: true

module Copilot
  class BetaSignupFormComponent < ApplicationComponent
    attr_reader :signup_url_path, :survey_questions, :survey_choice_detail_links, :preview_terms,
                :organizations, :enterprises, :signup_cta_text, :preview_terms_text
    delegate :avatar_for, to: :helpers
    renders_one :additional_inputs

    def initialize(signup_url_path:, survey_questions: nil, survey_choice_detail_links: nil, preview_terms: nil, organizations: nil, enterprises: nil, signup_cta_text: "Join waitlist", preview_terms_text: "")
      @signup_url_path = signup_url_path
      @survey_questions = survey_questions
      @survey_choice_detail_links = survey_choice_detail_links
      @preview_terms = preview_terms
      @organizations = organizations
      @enterprises = enterprises
      @signup_cta_text = signup_cta_text
      @preview_terms_text = preview_terms_text
    end

    memoize def visible_survey_questions
      survey_questions&.visible || []
    end

    def survey_choice_detail_link(survey_choice_id, opts = {})
      return nil unless survey_choice_detail_links && survey_choice_detail_links[survey_choice_id]

      link_to(
        survey_choice_detail_links[survey_choice_id].text,
        survey_choice_detail_links[survey_choice_id].url,
        opts
      )
    end

    def preview_terms_link
      return nil unless preview_terms

      link_to(preview_terms.text, preview_terms.url, class: "Link--inTextBlock")
    end

    def hide_windows_terminal_choice?(choice)
      choice.short_text == "windows_terminal" && !user_or_global_feature_enabled?(:copilot_chat_windows_terminal)
    end
  end
end
