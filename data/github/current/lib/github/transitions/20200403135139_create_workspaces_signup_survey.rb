# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200403135139_create_workspaces_signup_survey.rb -v | tee -a /tmp/create_workspaces_signup_survey.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200403135139_create_workspaces_signup_survey.rb -v -w | tee -a /tmp/create_workspaces_signup_survey.log
#
module GitHub
  module Transitions
    class CreateWorkspacesSignupSurvey < Transition

      SURVEY_SLUG = "workspaces"

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
            log "Would have saved survey \"#{survey.slug}\" with #{survey.attributes}."
          else
            survey.save!
            log "Saved survey \"#{survey.slug}\" with #{survey.attributes}."
          end

          generate_question(
            survey: survey,
            short_text: "programming_languages",
            text: "Which of these programming languages do you use?",
            choices: [
              "JavaScript/TypeScript/Node.js",
              "Python",
              "Java",
              "PHP",
              "C#",
              "C/C++",
              "Ruby",
              "Go",
              "Swift",
              "Kotlin",
              "Dart",
              "Rust",
              "Other(s)",
            ],
          )
        end

        log "Done!"
      end

      def generate_question(survey:, short_text:, text:, choices: [])
        question = survey.questions.build(
          display_order: survey.questions.count + 1,
          short_text: short_text,
          text: text,
        )

        question.save! unless dry_run

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
    opts.banner = "Usage: ruby lib/github/transitions/20200403135139_create_workspaces_signup_survey.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CreateWorkspacesSignupSurvey.new(options)
  transition.run
end
