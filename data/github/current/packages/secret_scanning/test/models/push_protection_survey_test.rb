# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/push_protection_survey_helper"

class PushProtectionSurveyTest < GitHub::TestCase
  include PushProtectionSurveyTestHelper

  fixtures do
    @monalisa = create(:user, login: "monalisa")
    @defunkt = create(:user, login: "defunkt")
  end

  context "#taken_by?" do
    test "returns true if the Survey is missing" do
      assert_nil T.unsafe(Survey).find_by_slug(PushProtectionSurvey::SLUG),
        "Expected survey to be missing from DB for this test"
      assert PushProtectionSurvey.taken_by?(@monalisa),
        "Expected taken_by? to return true when the Survey doesn't exist"
    end

    test "returns true if taken by a user" do
      # Create the survey model:
      create_push_protection_survey

      # "Take" the survey:
      answer_survey_for_user(@monalisa)

      assert PushProtectionSurvey.taken_by?(@monalisa),
        "Expected taken_by? to return true for a user who has taken the survey."

      refute PushProtectionSurvey.taken_by?(@defunkt),
        "Expected taken_by? to return false for a user who hasn't taken the survey."
    end
  end

  test "hide_for sets a hidden value in KV" do
    monalisa_hidden_key = PushProtectionSurvey.hide_key_for(@monalisa)
    refute GitHub.kv.exists(monalisa_hidden_key).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv

    PushProtectionSurvey.hide_for(@monalisa)
    assert GitHub.kv.exists(monalisa_hidden_key).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  test "hidden_by? returns true if the user has hidden the survey" do
    PushProtectionSurvey.hide_for(@monalisa)

    assert PushProtectionSurvey.hidden_by?(@monalisa),
      "Expected hidden_by? to return true"
  end
end
