# typed: true
# frozen_string_literal: true

require "test_helper"

class PlanningTrackingSurveyResultTest < GitHub::TestCase
  include GitHub::SurveyTestHelper

  setup do
    @user = create(:user)
    @org = create(:organization, admin: @user)

    @survey = create(:survey, slug: "hierarchy_and_roadmap")
    @tasklists_question = create(:survey_question, survey: @survey, short_text: "tasklists")
    @roadmap_question = create(:survey_question, survey: @survey, short_text: "roadmap")

    @membership = EarlyAccessMembership.new(
      actor: @user,
      member: @org,
      feature_slug: "hierarchy_and_roadmap",
      survey: @survey,
    )

    @hierarchy_answer = create(:survey_answer, question: @tasklists_question)
    @roadmap_answer = create(:survey_answer, question: @roadmap_question)
  end

  context "#survey_cache_key" do
    test "matches expected format" do
      assert_equal PlanningTrackingSurveyResult.survey_cache_key(2222, 3333), "projects-onboarding-2222-3333"
    end
  end

  context "#store_survey_results" do
    test "stores expected object when no survey answers" do
      membership_key = "projects-onboarding-#{@membership.member_id}-#{@membership.actor_id}"

      expected_value = {
        roadmap_feature_requested: true,
        tasklist_feature_requested: true,
      }

      PlanningTrackingSurveyResult.store_survey_results(@membership, [])

      actual_value = Memex::KV.store.get(membership_key).value { nil }
      assert_equal expected_value.to_json, actual_value
    end

    test "stores expected object when only hierarchy chosen" do
      membership_key = "projects-onboarding-#{@membership.member_id}-#{@membership.actor_id}"
      expected_value = {
        roadmap_feature_requested: false,
        tasklist_feature_requested: true,
      }

      PlanningTrackingSurveyResult.store_survey_results(@membership, [@hierarchy_answer])

      actual_value = Memex::KV.store.get(membership_key).value { nil }
      assert_equal expected_value.to_json, actual_value
    end

    test "stores expected object when only roadmap chosen" do
      membership_key = "projects-onboarding-#{@membership.member_id}-#{@membership.actor_id}"
      expected_value = {
        roadmap_feature_requested: true,
        tasklist_feature_requested: false,
      }

      PlanningTrackingSurveyResult.store_survey_results(@membership, [@roadmap_answer])

      actual_value = Memex::KV.store.get(membership_key).value { nil }
      assert_equal expected_value.to_json, actual_value
    end

    test "stores expected object when both chosen" do
      membership_key = "projects-onboarding-#{@membership.member_id}-#{@membership.actor_id}"
      expected_value = {
        roadmap_feature_requested: true,
        tasklist_feature_requested: true,
      }

      PlanningTrackingSurveyResult.store_survey_results(@membership, [@hierarchy_answer, @roadmap_answer])

      actual_value = Memex::KV.store.get(membership_key).value { nil }
      assert_equal expected_value.to_json, actual_value
    end
  end

  context "#get_survey_results" do
    test "returns default object when no KV value found" do
      expected_value = {
        roadmap_feature_requested: true,
        tasklist_feature_requested: true,
      }

      actual_value = PlanningTrackingSurveyResult.get_survey_results(@membership)

      assert_equal expected_value, actual_value
    end

    test "returns default object when invalid KV value found" do
      membership_key = "projects-onboarding-#{@membership.member_id}-#{@membership.actor_id}"

      Memex::KV.store.set(membership_key, "some-junk-text-string-blah")

      expected_value = {
        roadmap_feature_requested: true,
        tasklist_feature_requested: true,
      }

      actual_value = PlanningTrackingSurveyResult.get_survey_results(@membership)

      assert_equal expected_value, actual_value
    end

    test "returns expected object when object parsed from KV value" do
      PlanningTrackingSurveyResult.store_survey_results(@membership, [@roadmap_answer])
      expected_value = {
        roadmap_feature_requested: true,
        tasklist_feature_requested: false,
      }

      actual_value = PlanningTrackingSurveyResult.get_survey_results(@membership)

      assert_equal expected_value, actual_value
    end
  end
end
