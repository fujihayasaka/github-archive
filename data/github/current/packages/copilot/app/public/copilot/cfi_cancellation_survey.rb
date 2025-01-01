# typed: strict
# frozen_string_literal: true

module Copilot
  class CfiCancellationSurvey
    extend T::Sig

    SURVEY_SLUG = T.let("copilot_for_individuals_cancellation".freeze, String)
    QUESTIONS = T.let([
      {
        short_text: "user_type",
        text: "What is your user type?",
        choices: ["Free / Student", "Trial", "Paid"]
      },
      {
        short_text: "dev_environment",
        text: "Which development environment do you use?",
        choices: ["Visual Studio Code", "Visual Studio", "JetBrains", "Neovim", "Other (Please specify)"]
      },
      {
        short_text: "programming_language",
        text: "What programming languages do you usually use?",
        choices: [
          "Python",
          "JavaScript",
          "TypeScript",
          "Java",
          "Ruby",
          "Go",
          "C#",
          "Rust",
          "C++",
          "Html",
          "Other (Please specify)",
        ],
      },
      {
        short_text: "programming_experience",
        text: "What best describes your programming experience?",
        choices: [
          "Student / Intern learning to program",
          "0 to 2 years of professional programming experience",
          "3 to 5 years of professional programming experience",
          "6 to 10 years of professional programming experience",
          "11 to 15 years of professional programming experience",
          "More than 16 years of professional programming experience",
        ],
      },
      {
        short_text: "cancellation_reason",
        text: "We're sorry that your first experience with copilot did not meet your expectations, Would you tell us why?",
        choices: [
          "It wasn't clear how to use Copilot",
          "Copilot is distracting within my development environment",
          "I found an alternative",
          "It's too expensive",
          "I didn't like the quality of the suggestions",
          "Copilot didn't work well with other extensions",
          "I have privacy/security concerns",
          "I have access to copilot through my company",
          "Other: (Please specify)"
        ]
      },
      {
        short_text: "other_feedback",
        text: "Do you have other feedback, comments, or suggestions that you want to convey to us?",
        choices: ["other"]
      },
    ], T::Array[{ short_text: String, text: String, choices: T::Array[String] }])

    sig { params(dry_run: T::Boolean).returns(Survey) }
    def self.perform(dry_run: false)
      new(dry_run: dry_run).perform
    end

    sig { returns(T::Boolean) }
    attr_reader :dry_run

    sig { returns(Survey) }
    attr_reader :survey

    sig { params(dry_run: T::Boolean).void }
    def initialize(dry_run: false)
      @dry_run = T.let(dry_run, T::Boolean)
      @survey = T.let(Survey.find_or_initialize_by(slug: SURVEY_SLUG), Survey)
      @question_count = T.let(0, Integer)
    end

    sig { returns(Survey) }
    def perform
      if survey.persisted?
        GitHub.logger.info("Survey with slug #{SURVEY_SLUG} already exists, skipping creation.")
        return survey
      end

      survey.title = "GitHub Copilot Cancellation Feedback"

      if dry_run
        GitHub.logger.info("Would have saved survey #{survey.id} with #{survey.attributes}.")
      else
        survey.save!
        GitHub.logger.info("Saved survey #{survey.id} with #{survey.attributes}.")
      end

      QUESTIONS.each do |question|
        generate_question(
          short_text: question[:short_text],
          text: question[:text],
          choices: question[:choices]
        )
      end

      survey
    end

    private

    sig { params(short_text: String, text: String, choices: T::Array[String]).void }
    def generate_question(short_text:, text:, choices: ["other"])
      question = survey.questions.build(
        display_order: @question_count,
        short_text: short_text,
        text: text,
      )

      question.save! unless dry_run

      choices.each_with_index do |choice, i|
        choice = question.choices.build(short_text: choice, text: choice, display_order: i)

        choice.save! unless dry_run
      end

      log_message = "question #{question.short_text} with choices: #{question.choices.map(&:text).join(", ")}"
      if dry_run
        GitHub.logger.info("Would have saved " + log_message)
      else
        GitHub.logger.info("Saved " + log_message)
      end
      @question_count += 1
    end
  end
end
