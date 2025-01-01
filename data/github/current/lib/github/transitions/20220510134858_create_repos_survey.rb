# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220510134858_create_repos_survey.rb --verbose | tee -a /tmp/create_repos_survey.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220510134858_create_repos_survey.rb --verbose -w | tee -a /tmp/create_repos_survey.log
#
module GitHub
  module Transitions
    class CreateReposSurvey < Transition
      SURVEY_SLUG = "repositories_survey"

      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        if Survey.exists?(slug: SURVEY_SLUG)
          log "Survey with slug #{SURVEY_SLUG} already exists, skipping transition."
          return
        end

        Survey.transaction do
          survey = Survey.new(
            title: SURVEY_SLUG.titleize,
            slug: SURVEY_SLUG,
          )

          if dry_run
            log "Would have saved survey #{survey.id} with #{survey.attributes}."
          else
            survey.save!
            log "Saved survey #{survey.id} with #{survey.attributes}."
          end

          choices = [
            "Very difficult",
            "Difficult",
            "Neither easy nor difficult",
            "Easy",
            "Very easy",
          ]

          generate_question(survey: survey,
            short_text: "file_browsing",
            text: "How easy is it to browse files on GitHub.com?",
            choices: choices)

          generate_question(survey: survey,
            short_text: "file_editing",
            text: "How easy is it to edit a file on GitHub.com?",
            choices: choices)

          generate_question(survey: survey,
            short_text: "branch_creation",
            text: "How easy is it to create a new branch on GitHub.com?",
            choices: choices)

          generate_question(survey: survey,
            short_text: "additional_feedback",
            text: "(Optional) Please share any feedback about browsing or editing code on GitHub.com. What can we do to improve your overall satisfaction with GitHub?")

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

        if choices.length == 0
          # Add one dummy choice to satisfy the validation for survey answers at runtime
          choice = question.choices.build(short_text: "other", text: "other", display_order: 0)

          if !dry_run
            choice.save!
          end
        else
          choices.each_with_index do |choice, i|
            choice = question.choices.build(short_text: choice, text: choice, display_order: i)

            if !dry_run
              choice.save!
            end
          end
        end

        log_message = "question #{question.short_text} with choices:\n\t#{question.choices.map(&:attributes).join("\n\t")}"
        if dry_run
          log "Would have saved " + log_message
        else
          log "Saved " + log_message
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: create_repos_survey.rb [options]"

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

  transition = GitHub::Transitions::CreateReposSurvey.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::CreateReposSurvey.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
