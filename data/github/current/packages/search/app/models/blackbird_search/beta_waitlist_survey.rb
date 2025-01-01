# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  class BetaWaitlistSurvey
    SURVEY_SLUG = "blackbird_beta_waitlist"

    def self.find_survey
      Survey.find_by(slug: SURVEY_SLUG)
    end

    # Public: Creates the blackbird beta waitlist survey. Pass force to destroy
    # and re-create the survey. Be careful as this will delete all old survey
    # data.
    def self.create_survey(force: false)
      if force && survey = find_survey
        survey.destroy
      end

      survey = Survey.new(
        slug: SURVEY_SLUG,
        title: "GitHub Code Search Waitlist"
      )
      survey.save!

      display_order = 0

      # Question 1
      q = survey.questions.build(
        text: "How often do you search code using github.com?",
        short_text: "codesearch_usage",
        display_order: display_order += 1,
      )
      q.save!
      q.choices.build(text: "Every day", short_text: "daily").save!
      q.choices.build(text: "At least once a week", short_text: "once_per_week").save!
      q.choices.build(text: "Rarely", short_text: "rare").save!

      # Question 2
      q = survey.questions.build(
        text: "How often do you search code in an IDE or editor?",
        short_text: "codesearch_editor_usage",
        display_order: display_order += 1,
      )
      q.save!
      q.choices.build(text: "Every day", short_text: "daily").save!
      q.choices.build(text: "At least once a week", short_text: "once_per_week").save!
      q.choices.build(text: "Rarely", short_text: "rare").save!

      # Question 3
      q = survey.questions.build(
        text: "What other code search tools do you use?",
        short_text: "codesearch_other_tools",
        display_order: display_order += 1,
      )
      q.save!
      q.choices.build(text: "other", short_text: "other").save!

      # Question 4
      q = survey.questions.build(
        text: "Which IDEs or editors do you primarily use?",
        short_text: "codesearch_other_editors",
        display_order: display_order += 1,
      )
      q.save!
      q.choices.build(text: "other", short_text: "other").save!

      # Question 5
      #
      # NOTE: 'codesearch_preferred_search_features' is part of
      # SurveyQuestion::ACCEPT_MULTIPLE_ANSWERS which is what allows multiple
      # selection for this question.
      q = survey.questions.build(
        text: "What are your preferred ways to search code?",
        short_text: "codesearch_preferred_search_features",
        display_order: display_order += 1,
      )
      q.save!
      q.choices.build(text: "Matching one or more search words", short_text: "whole_word").save!
      q.choices.build(text: "Exactly matching multiple words in quotes", short_text: "exact_match").save!
      q.choices.build(text: "Matching regular expressions", short_text: "regex_match").save!
      q.choices.build(text: "Matching word patterns using wildcard characters like * or ?", short_text: "wildcard_match").save!
      q.choices.build(text: "Matching specific language constructs like classes and methods", short_text: "symbol_match").save!
      q.choices.build(text: "Other \(please specify\)", short_text: "other").save!

      # Question 6
      #
      # NOTE: 'codesearch_contexts' is part of
      # SurveyQuestion::ACCEPT_MULTIPLE_ANSWERS which is what allows multiple
      # selection for this question.
      q = survey.questions.build(
        text: "In which contexts would you find GitHub Code Search most valuable?",
        short_text: "codesearch_contexts",
        display_order: display_order += 1,
      )
      q.save!
      q.choices.build(text: "Searching my company’s code at work", short_text: "work_code").save!
      q.choices.build(text: "Searching open source code that I contribute to", short_text: "oss_contributed_code").save!
      q.choices.build(text: "Searching the world’s public code", short_text: "public_code").save!
      q.choices.build(text: "Other \(please specify\)", short_text: "other").save!

      survey
    end
  end
end
