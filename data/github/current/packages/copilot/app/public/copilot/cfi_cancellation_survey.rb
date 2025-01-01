# typed: strict
# frozen_string_literal: true

module Copilot
  class CfiCancellationSurvey

    SURVEY_SLUG = T.let("copilot_for_individuals_cancellation_2025".freeze, String)
    QUESTIONS = T.let([
      {
        short_text: "primary_reason",
        text: "What was the primary reason for canceling your GitHub Copilot subscription?",
        choices: [
          "Accuracy: Inaccurate or low quality code suggestions",
          "Tool and workflow compatibility: Copilot didn’t integrate well with my preferred tools, IDE, programming languages, frameworks, or it disrupted my workflow",
          "Pricing: The price did not match the value of the product",
          "Access through company: I got access to Copilot through my company",
          "Limited Models: Copilot didn’t offer access to specific AI models that I want to use (like Claude 3.5)",
          "Other: (please specify)"
        ]
      },
      {
        short_text: "response_accuracy",
        text: "How satisfied were you with the accuracy of Copilot's responses?",
        choices: ["Very satisfied", "Satisfied", "Neither satisfied nor dissatisfied", "Dissatisfied", "Very dissatisfied"]
      },
      {
        short_text: "model_satisfaction",
        text: "How satisfied were you with the AI models available in Copilot (like GPT-4o, Claude 3 Sonnet, Gemini)?",
        choices: ["Very satisfied", "Satisfied", "Neither satisfied nor dissatisfied", "Dissatisfied", "Very dissatisfied"],
      },
      {
        short_text: "user_experience",
        text: "How satisfied were you with Copilot’s user experience, including its ease of use and integration into your workflow?",
        choices: ["Very satisfied", "Satisfied", "Neither satisfied nor dissatisfied", "Dissatisfied", "Very dissatisfied"],
      },
      {
        short_text: "ai_development_solutions",
        text: "Which, if any, of the following AI development solutions are you currently using?",
        choices: ["Amazon Q", "ChatGPT", "Claude", "Gemini", "Cursor", "Other", "None of the above"]
      },
      {
        short_text: "other_feedback",
        text: "Do you have any additional feedback about your experience using or testing GitHub Copilot?",
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
        GitHub.logger.info("Would have saved #{log_message}")
      else
        GitHub.logger.info("Saved #{log_message}")
      end
      @question_count += 1
    end
  end
end
