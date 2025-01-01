# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220520083721_repositories_survey_add_question.rb --verbose | tee -a /tmp/repositories_survey_add_question.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220520083721_repositories_survey_add_question.rb --verbose -w | tee -a /tmp/repositories_survey_add_question.log
#
module GitHub
  module Transitions
    class RepositoriesSurveyAddQuestion < Transition
      SURVEY_SLUG = "repositories_survey"

      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        survey = Survey.find_by_slug(SURVEY_SLUG)
        if survey.nil?
          log "Survey with slug #{SURVEY_SLUG} doesn't exist, skipping transition."
          return
        end

        if survey.questions.exists?(short_text: "general_satisfaction")
          log "Survey with question `general_satisfaction` already exists, skipping transition."
          return
        end

        Survey.transaction do
          choices = [
            "Very dissatisfied",
            "Dissatisfied",
            "Neither satisfied nor dissatisfied",
            "Satisfied",
            "Very Satisfied",
          ]

          generate_question(survey: survey,
            short_text: "general_satisfaction",
            text: "How satisfied are you with GitHub.com?",
            choices: choices)

          reorder(survey) unless dry_run
        end

        log "Done!"
      end

      def generate_question(survey:, short_text:, text:, choices: [])
        question = survey.questions.build(
          display_order: survey.questions.count + 1, # Set an explicit order based on the order in which questions are added
          short_text: short_text,
          text: text,
        )

        if !dry_run
          question.save!
        end

        choices.each_with_index do |choice, i|
          choice = question.choices.build(short_text: choice, text: choice, display_order: i)

          if !dry_run
            choice.save!
          end
        end

        log_message = "question #{question.short_text} with choices:\n\t#{question.choices.map(&:attributes).join("\n\t")}"
        if dry_run
          log "Would have saved " + log_message
        else
          log "Saved " + log_message
        end
      end

      def reorder(survey)
        new_order = %w[
          file_browsing
          file_editing
          branch_creation
          general_satisfaction
          additional_feedback
        ]

        survey.questions.each do |question|
          question.update(display_order: new_order.index(question.short_text) + 1)
          log "Question #{question.short_text} new display order is #{question.display_order}"
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::RepositoriesSurveyAddQuestion.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::RepositoriesSurveyAddQuestion.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
