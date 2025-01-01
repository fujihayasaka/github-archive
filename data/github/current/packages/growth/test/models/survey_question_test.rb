# typed: true
# frozen_string_literal: true

require "test_helper"

class SurveyQuestionModelTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @other_user = create(:user)
    @question = create(:survey_question, text: "Do you know Git?")
  end

  context "#choices" do
    test "only includes active choices" do
      included = create(:survey_choice, question: @question, active: true)
      excluded = create(:survey_choice, question: @question, active: false)

      assert_equal [included], @question.choices
    end
  end

  context "#first_choice" do
    test "returns first active choice by display order" do
      included_second = create(:survey_choice, question: @question, active: true, display_order: 2)
      excluded = create(:survey_choice, question: @question, active: false)
      included_first = create(:survey_choice, question: @question, active: true, display_order: 1)

      assert_equal included_first, @question.first_choice
    end
  end

  context "Question with 'other' field" do
    test "returns 'other' choice" do
      9.times { |i| create(:survey_choice, question: @question, text: i) }
      choice = create(:survey_choice, question: @question, text: "Other One")
      assert_equal @question.other_choice, choice
    end

    test "returns 'other' answers" do
      choice = create(:survey_choice, question: @question, text: "other")
      other_text = ["Hello", "is it ME", "you are looking for", "   ",
                    " hello ", " "]

      other_text.each do |answer|
        create(:survey_answer,
          user: @user,
          choice: choice,
          question: @question,
          other_text: answer,
        )
      end

      assert_equal ["hello", "is it ME", "you are looking for"], @question.other_answers_summary
    end

    test "handles `nil` other_answer values" do
      choice = create(:survey_choice, question: @question, text: "other")

      create(:survey_answer,
        user: @user,
        choice: choice,
        question: @question,
        other_text: nil,
      )

      create(:survey_answer,
        user: @user,
        choice: choice,
        question: @question,
        other_text: nil,
      )

      assert_equal [], @question.other_answers_summary
    end

    test "limits responses" do
      choice = create(:survey_choice, question: @question, text: "other")

      excluded = create(:survey_answer,
        user: @user,
        choice: choice,
        question: @question,
        other_text: "Hello",
      )

      included = create(:survey_answer,
        user: @user,
        choice: choice,
        question: @question,
        other_text: "is it ME",
      )

      assert_equal ["is it ME"], @question.other_answers_summary(limit: 1)
    end

    test "returns shuffled choices" do
      20.times { |i| create(:survey_choice, question: @question, text: i) }
      create(:survey_choice, question: @question, text: "Other One", display_order: 1)

      shuffled_choices = @question.shuffled_choices
      assert_equal @question.other_choice, shuffled_choices.last
      refute_equal Array.new(20, &:to_s), shuffled_choices[0..19].map(&:text)
    end
  end

  context "#multiple_choice?" do
    test "true when there is more than one choice" do
      question = create(:survey_question, text: "Do you code?")
      create(:survey_choice, question: question, text: "Yes")
      create(:survey_choice, question: question, text: "No")
      assert_equal 2, question.choices.count

      assert question.multiple_choice?
    end

    test "false otherwise" do
      question = create(:survey_question, text: "Do you code?")
      choice = create(:survey_choice, question: question, text: "Sometimes")
      assert_equal 1, question.choices.count

      refute question.multiple_choice?
    end
  end

  context "#max_acceptable_answers" do
    test "returns one if question doesn't accept multiple answers" do
      assert_equal 1, @question.max_acceptable_answers
    end

    test "returns explicit max if question has one in MAX_ANSWERS" do
      SurveyQuestion.stub_consts({
        ACCEPT_MULTIPLE_ANSWERS: [@question.short_text],
        MAX_ANSWERS: { "#{@question.short_text}".to_sym => 2 }
      }) do
        assert_equal 2, @question.max_acceptable_answers
      end
    end

    test "returns 100_000 if question does not have a set max" do
      SurveyQuestion.stub_const(:ACCEPT_MULTIPLE_ANSWERS, [@question.short_text]) do
        assert_equal 100_000, @question.max_acceptable_answers
      end
    end
  end
end
