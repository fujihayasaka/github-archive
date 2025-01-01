# typed: true
# frozen_string_literal: true

require "test_helper"

class Survey::TestTrue
  def self.show_survey?(user)
    true
  end
end

class Survey::TestFalse
  def self.show_survey?(user)
    false
  end
end

class SurveyTest < GitHub::TestCase
  fixtures do
    @survey   = create(:survey, slug: "first_run")
    @question = create(:survey_question, text: "Do you know Git?", survey: @survey)
    @batch_survey = create(:survey, slug: "batch_survey")
    @batch_question = create(:survey_question, text: "Do you know Git?", survey: @batch_survey)
    @user  = create(:user)
    @user1 = create(:user)
  end

  context ".batch_csv_dump" do
    test "return a subsection of the survey" do
      choice = create(:survey_choice, question: @batch_question, text: "First choice text")
      choice2 = create(:survey_choice, question: @batch_question, text: "Second choice text")
      create(:survey_answer,
        survey: @batch_survey,
        question: @batch_question,
        choice: choice,
        user: @user
      )

      create(:survey_answer,
        survey: @batch_survey,
        question: @batch_question,
        choice: choice2,
        user: @user1
      )

      csv_dump1 = @batch_survey.batch_csv_dump(0, 1)
      csv_dump2 = @batch_survey.batch_csv_dump(1, 1)

      assert_includes csv_dump1, "First choice text"
      assert_includes csv_dump2, "Second choice text"
    end

    test "return a subsection of the survey with multiple answers" do
      choice = create(:survey_choice, question: @batch_question, text: "First choice text")
      choice2 = create(:survey_choice, question: @batch_question, text: "Second choice text")
      # Create a group for user
      group = create(:survey_group, survey: @batch_survey, user: @user)
      group2 = create(:survey_group, survey: @batch_survey, user: @user1)

      create(:survey_answer,
        survey: @batch_survey,
        question: @batch_question,
        choice: choice,
        user: @user,
        survey_group: group
      )

      create(:survey_answer,
        survey: @batch_survey,
        question: @batch_question,
        choice: choice2,
        user: @user,
        survey_group: group
      )

      create(:survey_answer,
        survey: @batch_survey,
        question: @batch_question,
        choice: choice,
        user: @user1,
        survey_group: group2
      )

      csv_dump = @batch_survey.batch_csv_dump(0, 1)
      csv_dump1 = @batch_survey.batch_csv_dump(1, 1)
      assert_includes csv_dump, "First choice text"
      assert_includes csv_dump, "Second choice text"
      assert_includes csv_dump1, "First choice text"
      refute_includes csv_dump1, "Second choice text"
    end
  end
  context ".csv_dump" do

    test "allows multiple answers per question through SurveyGroup" do
      choice = create(:survey_choice, question: @question, text: "First choice text")
      other_choice = create(:survey_choice, question: @question, text: "Second choice text")
      group = create(:survey_group, survey: @survey, user: @user)
      create(:survey_answer,
        survey: @survey,
        question: @question,
        user: @user,
        survey_group: group,
        choice: choice,
      )
      create(:survey_answer,
        survey: @survey,
        question: @question,
        user: @user,
        survey_group: group,
        choice: other_choice,
      )

      csv_dump = @survey.csv_dump
      assert_includes csv_dump, "First choice text"
      assert_includes csv_dump, "Second choice text"
    end

    test "joins text for questions with multiple answer into a single row" do
      first_choice = create(:survey_choice, question: @question, text: "First choice text")
      second_choice = create(:survey_choice, question: @question, text: "Second choice text")
      last_choice = create(:survey_choice, question: @question, text: "Last choice text")

      create(:survey_answer,
        survey: @survey,
        question: @question,
        user: @user,
        choice: first_choice,
      )

      create(:survey_answer,
        survey: @survey,
        question: @question,
        user: @user,
        choice: second_choice,
      )

      create(:survey_answer,
        survey: @survey,
        question: @question,
        user: @user,
        choice: last_choice,
      )

      heading, first_row, extra_rows = @survey.csv_dump.split("\n")
      assert_nil extra_rows
      assert_includes first_row, "First choice text"
      assert_includes first_row, "Second choice text"
      assert_includes first_row, "Last choice text"
    end

    test "adds entry for individual question answers" do
      ship_question = create(:survey_question, text: "Ready?", survey: @survey)
      ship_yes = create(:survey_choice, question: ship_question, text: "Ship it!")
      ship_no = create(:survey_choice, question: ship_question, text: "No")

      swag_question = create(:survey_question, text: "More Swag?", survey: @survey)
      swag_yes = create(:survey_choice, question: swag_question, text: "More please")
      swag_no = create(:survey_choice, question: swag_question, text: "No..")

      create(:survey_answer,
        survey: @survey,
        question: ship_question,
        user: @user,
        choice: ship_yes,
      )

      create(:survey_answer,
        survey: @survey,
        question: swag_question,
        user: @user,
        choice: swag_yes,
      )

      csv_dump = @survey.csv_dump
      assert_includes csv_dump, ",Ship it!,"
      assert_includes csv_dump, ",More please,"
    end

  end

  context ".show_survey?" do
    test "returns true when the corresponding survey returns true" do
      Survey.stub(:one_percent?, true) do
        assert_equal true, Survey.show_survey?(slug: "test_true", user: create(:user)), "should find Survey::TestTrue and return true"
      end
    end

    test "returns false when the corresponding survey returns false" do
      Survey.stub(:one_percent?, true) do
        assert_equal false, Survey.show_survey?(slug: "test_false", user: create(:user)), "should find Survey::TestFalse and return false"
      end
    end

    test "handles unknown surveys" do
      Survey.stub(:one_percent?, true) do
        assert_equal true, Survey.show_survey?(slug: "test_unknown_survey", user: create(:user)), "should not find survey but return true instead"
      end
    end
  end

  test "must have a unique slug" do
    create(:survey, slug: "kangaroo_adoption")

    survey = build(:survey, slug: "kangaroo_adoption")
    refute survey.valid?
    refute_empty survey.errors[:slug]

    survey = build(:survey, slug: "kangaroo_adoption".upcase)
    refute survey.valid?
    refute_empty survey.errors[:slug]
  end

  test "rejects slug containing emoji" do
    survey = build(:survey, slug: "🐹")
    refute survey.valid?
    refute_empty survey.errors[:slug]
  end

  context "returning the questions answered by a user" do
    test "returns [] when user hasn't answered any of the questions" do
      assert_equal [], @survey.questions_answered_by(@user)
    end

    test "returns array of questions answered by the user" do
      @choice = create(:survey_choice, question: @question, text: "Yes")
      create(:survey_answer, survey: @survey, question: @question, choice: @choice, user: @user)
      assert_equal [@question], @survey.questions_answered_by(@user)
    end
  end

  context "returning the questions yet to be answered by a user" do
    test "returns all survey questions when user hasn't answered any of the questions" do
      assert_equal @survey.questions, @survey.questions_to_answer(@user)
    end

    test "returns array of questions remaining" do
      @choice = create(:survey_choice, question: @question, text: "Yes")
      create(:survey_answer, survey: @survey, question: @question, choice: @choice, user: @user)

      another_question = create(:survey_question, text: "Do you know kung fu?", survey: @survey)

      assert_equal [another_question], @survey.questions_to_answer(@user)
    end
  end

  test "returns the (1 based) order position of a question in a survey" do
    assert_equal 1, @survey.question_num(@question)
  end

  context "#taken_by?" do
    test "true if the survey has any answers recorded for a user" do
      @choice = create(:survey_choice, question: @question, text: "Yes")
      create(:survey_answer, survey: @survey, question: @question, choice: @choice, user: @user)
      assert @survey.taken_by?(@user)
    end

    test "false otherwise" do
      user = create(:user)
      refute @survey.taken_by?(user)
    end
  end

  context "#save_answers" do
    test "saves a collection of answers for the survey" do
      first_question  = create(:survey_question, text: "Do you know Git?", survey: @survey)
      first_choice    = create(:survey_choice, question: first_question, text: "Yes")
      second_question = create(:survey_question, text: "Do program?", survey: @survey)
      second_choice   = create(:survey_choice, question: second_question, text: "Yes")

      answer_hash = {
        first_question.id.to_s => {
          "choice" => first_choice.id,
        },
        second_question.id.to_s => {
          "choice" => second_choice.id,
          "other" => { second_choice.id.to_s => "lolcats" },
        },
        "90210" => { # A id that won't be a question id, it should be ignored
          "choice" => "1",
          "other" => { "1" => "Sorry so sloppy" },
        },
      }

      answers = @survey.save_answers(@user, answer_hash)

      assert_equal 2, answers.count
      answers.each do |answer|
        assert answer.instance_of?(SurveyAnswer)
      end

      assert_equal 2, @survey.questions_answered_by(@user).count

      assert_equal first_choice, first_question.answers.first.choice
      assert_nil first_question.answers.first.other_text
      assert_equal @user, first_question.answers.first.user

      assert_equal second_choice, second_question.answers.first.choice
      assert_equal "lolcats", second_question.answers.first.other_text
      assert_equal @user, second_question.answers.first.user
    end

    test "allows multiple answer choices for a single question" do
      first_question  = create(:survey_question, text: "What are you interested in?", survey: @survey)
      first_choice    = create(:survey_choice, question: first_question, text: "Development")
      second_choice   = create(:survey_choice, question: first_question, text: "Design")

      answer_hash = {
        first_question.id.to_s => {
          "choices" => [first_choice.id, second_choice.id],
        },
      }

      assert @survey.save_answers(@user, answer_hash)
      assert_equal 2, first_question.answers.count
    end

    test "allows multiple answer choices for a single question and records other text" do
      first_question  = create(:survey_question, text: "What are you interested in?", survey: @survey)
      first_choice    = create(:survey_choice, question: first_question, text: "Development")
      second_choice   = create(:survey_choice, question: first_question, text: "Other", short_text: "other")

      answer_hash = {
        first_question.id.to_s => {
          "choices" => [first_choice.id, second_choice.id],
          "other" => { second_choice.id.to_s => "other text" }
        },
      }

      assert @survey.save_answers(@user, answer_hash)
      assert_equal 2, first_question.answers.count
      assert_nil first_question.answers.find_by(choice_id: first_choice.id).other_text
      assert_equal "other text", first_question.answers.find_by(choice_id: second_choice.id).other_text
    end

    test "can specify one choice in the choices list" do
      question  = create(:survey_question, text: "What are you interested in?", survey: @survey)
      choice    = create(:survey_choice, question: question, text: "Development")

      answer_hash = {
        question.id.to_s => {
          "choices" => choice.id,
        },
      }

      assert @survey.save_answers(@user, answer_hash)
      assert_equal 1, question.answers.count
    end

    test "accepts answers from multiple users" do
      question  = create(:survey_question, text: "What are you interested in?", survey: @survey)
      choice    = create(:survey_choice, question: question, text: "Development")
      user_2    = create(:user)

      answer_hash = {
        question.id.to_s => {
          "choices" => choice.id,
        },
      }

      assert @survey.save_answers(@user, answer_hash)
      assert @survey.save_answers(user_2, answer_hash)
      assert_equal 2, @survey.answers.count
    end

    test "can specify an array of selections" do
      question  = create(:survey_question, text: "What are you interested in?", survey: @survey)
      choice    = create(:survey_choice, question: question, text: "Development")

      answer_hash = {
        question.id.to_s => {
          "choice" => choice.id,
          "selections" => %w[a b],
        },
      }

      assert @survey.save_answers(@user, answer_hash)
      assert_equal 1, question.answers.count
      assert_equal %w[a b], question.answers.first.selections
    end

    test "returns false if there's an error saving" do
      question  = create(:survey_question, text: "What are you interested in?", survey: @survey)
      choice    = create(:survey_choice, question: question, text: "Development")

      SurveyAnswer.any_instance.stubs(:valid?).returns(false)

      answer_hash = {
        question.id => {
          "choices" => choice.id,
        },
      }

      refute @survey.save_answers(@user, answer_hash)
      assert_equal 0, question.answers.count
    end

    test "ignores unanswered questions" do
      first_question  = create(:survey_question, text: "Is this a test?", survey: @survey)
      first_choice    = create(:survey_choice, question: first_question, text: "yes")
      second_question = create(:survey_question, text: "Is this cool?", survey: @survey)
      create(:survey_choice, question: second_question, text: "yes")

      answer_hash = {
        first_question.id.to_s => {
          "choice" => first_choice.id,
        },
        second_question.id.to_s => {
          "choice" => "",
        },
      }

      assert @survey.save_answers(@user, answer_hash)

      assert_equal 1, first_question.answers.count
      assert_equal 0, second_question.answers.count
    end
  end
end
