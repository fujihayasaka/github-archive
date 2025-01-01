# typed: true
# frozen_string_literal: true

require "test_helper"

class PlanSuggestionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
  end

  context "#recommended_plan" do
    test "returns :education_student when user_self_description is education_student" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        user_self_description: "education_student",
      )

      assert_equal :education_student, plan_suggestion.recommended_plan
    end

    test "returns :education_teacher when user_self_description is education_teacher" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        user_self_description: "education_teacher",
      )

      assert_equal :education_teacher, plan_suggestion.recommended_plan
    end

    test "returns business if user_self_description is other and team size 20-50" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        user_self_description: "other",)
      assert_equal :business, plan_suggestion.recommended_plan
    end

    test "returns business if user_self_description is working_developer and team size 20-50" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        user_self_description: "working_developer",)
      assert_equal :business, plan_suggestion.recommended_plan
    end

    test "returns Business Plus plan if team size is 50+" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "50+",
      )

      assert_equal :business_plus, plan_suggestion.recommended_plan
    end

    test "returns Business plan when team size is 20-50" do
      assert_equal :business, PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
      ).recommended_plan
    end

    test "returns Free plan when team size is 1" do
      assert_equal :free, PlanSuggestion.new(
        user: @user,
        team_size: "1",
      ).recommended_plan
    end
  end

  context "#single_person?" do
    test "returns true if team size is 1" do
      assert PlanSuggestion.new(
        user: @user,
        team_size: "1",
      ).single_person?
    end
  end

  context "#must_discuss_plan?" do
    test "returns true if team size is greater than 50" do
      assert PlanSuggestion.new(user: @user, team_size: "50+").must_discuss_plan?
      refute PlanSuggestion.new(user: @user, team_size: "20-50").must_discuss_plan?
    end
  end

  context "#recommend_plan" do
    test "publishes recommended plan event" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        user_self_description: "education_teacher",
        purpose: ["copilot"],
      )

      plan_suggestion.recommend_plan

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(@user),
          recommended_plan: "education_teacher",
          team_size: "20-50",
          user_self_description: "education_teacher",
          purpose: ["copilot"],
        },
        schema: "github.v1.RecommendedPlan"
      )
    end
  end
end
