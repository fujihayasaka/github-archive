# typed: true
# frozen_string_literal: true

module Beta
  class SignupFormComponent < ApplicationComponent
    attr_reader :survey, :adminable_organizations, :survey_header, :survey_choice_detail_links

    delegate :avatar_for, to: :helpers

    def initialize(survey:, adminable_organizations: nil, survey_header: nil, survey_choice_detail_links: nil)
      @survey = survey
      @adminable_organizations = adminable_organizations
      @survey_header = survey_header
      @survey_choice_detail_links = survey_choice_detail_links
    end

    def survey_choice_detail_link(survey_choice_id, opts = {})
      return nil unless survey_choice_detail_links && survey_choice_detail_links[survey_choice_id]

      link_to(
        survey_choice_detail_links[survey_choice_id].text,
        survey_choice_detail_links[survey_choice_id].url,
        opts
      )
    end
  end
end
