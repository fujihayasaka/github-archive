# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Readme::NominationSurveyTest < GitHub::TestCase
  context ".survey" do
    test "returns a survey if it exists" do
      Site::Readme::NominationSurvey.create!(dry_run: false)

      survey = Survey.find_by(slug: Site::Readme::NominationSurvey::SLUG)

      assert_equal survey, Site::Readme::NominationSurvey.survey
      assert_equal Survey, Site::Readme::NominationSurvey.survey.class
    end

    test "preloads questions and choices to avoid N+1" do
      Site::Readme::NominationSurvey.create!(dry_run: false)

      survey = Site::Readme::NominationSurvey.survey

      assert_query_count(0) do
        survey_questions = survey.questions
        survey_questions.map do |survey_question|
          assert SurveyQuestion, survey_question.class

          survey_question.choices.each do |survey_choice|
            assert SurveyChoice, survey_choice.class
          end
        end
      end
    end

    test "returns nil if the survey does not exist" do
      assert_nil Site::Readme::NominationSurvey.survey
    end
  end

  context ".create!" do
    context "dry run" do
      test "returns a survey" do
        survey = Site::Readme::NominationSurvey.create!(dry_run: true)

        assert_equal Survey, survey.class
      end

      test "does not persist a survey or questions" do
        assert_equal 0, Survey.count
        assert_equal 0, SurveyQuestion.count
        assert_equal 0, SurveyChoice.count

        Site::Readme::NominationSurvey.create!(dry_run: true)

        assert_equal 0, Survey.count
        assert_equal 0, SurveyQuestion.count
        assert_equal 0, SurveyChoice.count
      end
    end

    context "real run... dry runs are for chumps..." do
      test "returns a survey" do
        survey = Site::Readme::NominationSurvey.create!(dry_run: false)

        assert_equal Survey, survey.class
      end

      test "persists the survey and questions" do
        assert_equal 0, Survey.count
        assert_equal 0, SurveyQuestion.count
        assert_equal 0, SurveyChoice.count

        Site::Readme::NominationSurvey.create!(dry_run: false)

        assert_equal 1, Survey.count
        assert_equal 6, SurveyQuestion.count
        assert_equal 9, SurveyChoice.count

        assert Survey.find_by(slug: Site::Readme::NominationSurvey::SLUG)

        Site::Readme::NominationSurvey::QUESTION_NAMES.each do |question_short_text|
          survey_question = SurveyQuestion.find_by(short_text: question_short_text)

          assert survey_question

          if T.must(survey_question).short_text == "nominee_role"
            survey_choice_short_texts = T.must(survey_question).choices.pluck(:short_text)
            survey_choice_short_texts.each do |survey_choice_short_text|
              assert_includes Site::Readme::NominationSurvey::NOMINEE_ROLE_CHOICES, survey_choice_short_text
            end
          end
        end
      end
    end
  end
end
