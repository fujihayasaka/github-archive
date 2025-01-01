# typed: true
# frozen_string_literal: true

require "test_helper"

class PlanSuggestionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
  end

  context "#recommended_plan" do
    test "returns :education_student when education_type is student" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: "education_student",
        tools: ["enterprise_security"]
      )

      assert_equal :education_student, plan_suggestion.recommended_plan
    end

    test "returns :education_teacher when education_type is teacher" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: "education_teacher",
        tools: ["enterprise_security"]
      )

      assert_equal :education_teacher, plan_suggestion.recommended_plan
    end

    test "returns :education_student when user_self_description is education_student" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: nil,
        tools: ["enterprise_security"],
        user_self_description: "education_student",
      )

      assert_equal :education_student, plan_suggestion.recommended_plan
    end

    test "returns :education_teacher when user_self_description is education_teacher" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: nil,
        tools: ["enterprise_security"],
        user_self_description: "education_teacher",
      )

      assert_equal :education_teacher, plan_suggestion.recommended_plan
    end

    test "returns enterprise if education is not applicable" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: "education_na",
        tools: ["enterprise_security"]
      )

      assert_equal :business_plus, plan_suggestion.recommended_plan
    end

    test "returns Enterprise plan if enterprise_security tool is selected" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: nil,
        tools: ["enterprise_security"]
      )

      assert_equal :business_plus, plan_suggestion.recommended_plan
    end

    test "returns Business Plus plan if team size is 50+" do
      plan_suggestion = PlanSuggestion.new(
        user: @user,
        team_size: "50+",
        education_type: nil,
        tools: []
      )

      assert_equal :business_plus, plan_suggestion.recommended_plan
    end

    test "returns Business plan when team size is not 50 and enterprise_security is not a selected tool" do
      assert_equal :business, PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: nil,
        tools: ["community"]
      ).recommended_plan

      refute_equal :business, PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: nil,
        tools: ["enterprise_security"]
      ).recommended_plan
    end

    test "returns Free plan when team size is 1 and enterprise_security is not a selected tool" do
      assert_equal :free, PlanSuggestion.new(
        user: @user,
        team_size: "1",
        education_type: nil,
        tools: ["community"]
      ).recommended_plan

      refute_equal :free, PlanSuggestion.new(
        user: @user,
        team_size: "1",
        education_type: nil,
        tools: ["enterprise_security"]
      ).recommended_plan
    end
  end

  context "#single_person?" do
    test "returns true if team size is 1 and does not need enterprise_security" do
      assert PlanSuggestion.new(
        user: @user,
        team_size: "1",
        education_type: nil,
        tools: ["community"]
      ).single_person?

      refute PlanSuggestion.new(
        user: @user,
        team_size: "1",
        education_type: nil,
        tools: ["enterprise_security"]
      ).single_person?

      refute PlanSuggestion.new(
        user: @user,
        team_size: "20-50",
        education_type: nil,
        tools: ["community"]
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
        education_type: "education_teacher",
        tools: ["enterprise_security"],
        user_self_description: "education_teacher",
      )

      plan_suggestion.recommend_plan

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(@user),
          recommended_plan: "education_teacher",
          team_size: "20-50",
          education_type: "education_teacher",
          tools: ["enterprise_security"],
          user_self_description: "education_teacher",
        },
        schema: "github.v1.RecommendedPlan"
      )
    end
  end
end
