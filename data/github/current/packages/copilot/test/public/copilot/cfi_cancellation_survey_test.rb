# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::CfiCancellationSurveyTest < GitHub::TestCase
  include GitHub::LoggerHelper

  test "creates the survey, questions, and choices" do
    logs = capture_logs do
      assert_changes -> { Survey.count }, from: 0, to: 1 do
        assert_changes -> { SurveyQuestion.count }, from: 0, to: 6 do
          assert_changes -> { SurveyChoice.count }, from: 0, to: 35 do
            Copilot::CfiCancellationSurvey.perform
          end
        end
      end
    end

    assert_match "Saved survey", logs
    Copilot::CfiCancellationSurvey::QUESTIONS.each do |question|
      assert_match "Saved question #{question[:short_text]} with choices: #{question[:choices].join(", ")}", logs
    end
  end

  context "when doing a dry run" do
    test "does not create anything" do
      logs = capture_logs do
        assert_no_changes -> { Survey.count } do
          assert_no_changes -> { SurveyQuestion.count } do
            assert_no_changes -> { SurveyChoice.count } do
              Copilot::CfiCancellationSurvey.perform(dry_run: true)
            end
          end
        end
      end

      assert_match "Would have saved survey", logs
      Copilot::CfiCancellationSurvey::QUESTIONS.each do |question|
        assert_match "Would have saved question #{question[:short_text]} with choices: #{question[:choices].join(", ")}", logs
      end
    end
  end

  context "when the survey already exists" do
    test "does not create anything" do
      create(:survey, slug: Copilot::CfiCancellationSurvey::SURVEY_SLUG)

      logs = capture_logs do
        assert_no_changes -> { Survey.count } do
          assert_no_changes -> { SurveyQuestion.count } do
            assert_no_changes -> { SurveyChoice.count } do
              Copilot::CfiCancellationSurvey.perform
            end
          end
        end
      end

      assert_match "Survey with slug #{Copilot::CfiCancellationSurvey::SURVEY_SLUG} already exists, skipping creation.", logs
    end
  end
end if GitHub.copilot_enabled?
