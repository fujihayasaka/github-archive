# typed: true
# frozen_string_literal: true

module MergeQueueBeta
  class Survey
    SURVEY_SLUG = "merge_queue_beta"

    def self.find_survey
      ::Survey.find_by(slug: SURVEY_SLUG)
    end

    def self.create_survey(dry_run:)
      survey = ::Survey.new(
        title: "Merge Queue Beta",
        slug: SURVEY_SLUG,
      )
      survey.save! unless dry_run

      q = survey.questions.build(
        text: "Repository Response",
        short_text: "repository",
        display_order: 1,
      )
      q.save! unless dry_run

      c = q.choices.build(text: "Repository (optional)", short_text: "other")
      c.save! unless dry_run

      survey
    end
  end
end
