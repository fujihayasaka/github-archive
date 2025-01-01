# typed: true
# frozen_string_literal: true

require "test_helper"

class SurveyAnswerTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @question = create(:survey_question, short_text: "other")
    @choice = create(:survey_choice, {
      question: @question,
      text: "other",
      short_text: "other",
    })
  end

  context ".for" do
    test "returns answers for a given user" do
      user     = create(:user)
      included = create(:survey_answer, user: user)
      excluded = create(:survey_answer, user: create(:user))

      assert_equal [included], SurveyAnswer.for(user)
    end
  end

  context "#other_text" do
    test "forces the encoding to be UTF-8" do
      answer = create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        other_text: "beep-boop".b,
      })

      assert_equal answer.other_text.encoding, Encoding::UTF_8
      assert_equal answer.normalized_other_text.encoding, Encoding::UTF_8
    end
  end

  context "#selections=" do
    test "persists multiple selections" do
      answer = create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        selections: %w[a b],
      })

      assert_equal %w[a b], answer.selections
    end

    test "handles commas" do
      answer = create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        selections: ["a,b", "c"],
      })

      assert_equal ["a,b", "c"], answer.selections
    end

    test "handles nil" do
      answer = create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        selections: nil,
      })

      assert_equal [], answer.selections

      answer = create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        other_text: nil,
      })

      assert_equal [], answer.selections
    end

    test "handles strings" do
      answer = create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        selections: "a",
      })

      assert_equal ["a"], answer.selections
    end

    test "handles empty strings" do
      answer = create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        selections: "",
      })

      assert_equal [], answer.selections
    end

    test "aggregates consistently" do
      create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        selections: %w[a b],
      })

      create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        selections: %w[b a],
      })

      create(:survey_answer, {
        user: @user,
        choice: @choice,
        question: @question,
        selections: %w[a c],
      })

      assert_equal ["a,b", "a,c"], @question.other_answers_summary
    end
  end

  context "#save_as_group" do
    test "it saves all answers with the same group_id" do
      user = create :user
      survey = create :survey
      question_1 = create :survey_question, survey: survey
      question_2 = create :survey_question, survey: survey
      choice_1 = create :survey_choice, question: question_1
      choice_2 = create :survey_choice, question: question_2
      answers = [
        { question_id: question_1.id, choice_id: choice_1.id, other_text: "foo" },
        { question_id: question_2.id, choice_id: choice_2.id, other_text: "foo" },
      ]

      result = SurveyAnswer.save_as_group(user.id, survey.id, answers)
      assert result.is_a?(SurveyGroup)
      assert_equal T.must(SurveyAnswer.last).survey_group_id, SurveyAnswer.all[-2].survey_group_id
    end

    test "it saves at most 3000 chars from answers" do
      user = create :user
      survey = create :survey
      question_1 = create :survey_question, survey: survey
      question_2 = create :survey_question, survey: survey
      choice_1 = create :survey_choice, question: question_1
      choice_2 = create :survey_choice, question: question_2
      answers = [
        { question_id: question_1.id, choice_id: choice_1.id, other_text: "a" * 5000 },
        { question_id: question_2.id, choice_id: choice_2.id, other_text: "b" * 300 },
      ]

      result = SurveyAnswer.save_as_group(user.id, survey.id, answers)
      assert result.is_a?(SurveyGroup)
      assert_equal T.must(SurveyAnswer.first).other_text, "a" * 3000
      assert_equal T.must(SurveyAnswer.last).other_text, "b" * 300
    end

    test "it does not save answers if a choice is invalid" do
      user = create(:user)
      survey = create(:survey)
      question_1 = create(:survey_question, survey: survey)
      question_2 = create(:survey_question, survey: survey)
      choice_for_question_1 = create(:survey_choice, question: question_1)
      answers = [
        { question_id: question_1.id, choice_id: choice_for_question_1.id, other_text: "foo" },
        { question_id: question_2.id, choice_id: choice_for_question_1.id, other_text: "foo" },
      ]

      result = SurveyAnswer.save_as_group(user.id, survey.id, answers)
      assert_equal false, result
      assert_equal 0, SurveyGroup.count
      assert_equal 0, SurveyAnswer.count
    end
  end

  context "instrumentation" do
    test "instruments create events" do
      events = subscribe "survey_answer.create"
      user = create :user
      survey_answer = create :survey_answer, user: user
      expected_payload = { survey_slug: survey_answer.survey.slug }
      assert event = events.pop, "An event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "validation" do
    test "valid when choice belongs to question" do
      question = create(:survey_question)
      answer = build(:survey_answer,
        question: question,
        choice: create(:survey_choice, question: question),
      )

      assert_predicate answer, :valid?
    end

    test "invalid when choice does not belong to question" do
      question = create(:survey_question)
      other_question = create(:survey_question)
      answer = build(:survey_answer,
        question: question,
        choice: create(:survey_choice, question: other_question),
      )

      refute_predicate answer, :valid?
      assert_equal "Choice is invalid for question", answer.errors.full_messages.to_sentence
    end
  end
end
