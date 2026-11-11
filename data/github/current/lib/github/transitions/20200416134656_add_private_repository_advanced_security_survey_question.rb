# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200416134656_add_private_repository_advanced_security_survey_question.rb --verbose | tee -a /tmp/add_private_repository_advanced_security_survey_question.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200416134656_add_private_repository_advanced_security_survey_question.rb --verbose -w | tee -a /tmp/add_private_repository_advanced_security_survey_question.log
#
module GitHub
  module Transitions
    class AddPrivateRepositoryAdvancedSecuritySurveyQuestion < Transition
      SURVEY_SLUG = "code_scanning"
      QUESTION_SHORT_TEXT = "private_repositories"

      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        survey = Survey.find_by(slug: SURVEY_SLUG)

        unless survey.present?
          log "Survey with slug #{SURVEY_SLUG} does not exist, skipping transition."
          return
        end

        question = survey.questions.find_by(short_text: QUESTION_SHORT_TEXT)

        if question.present?
          log "#{QUESTION_SHORT_TEXT} question already exists, skipping transition."
          return
        end

        Survey.transaction do
          previous_questions = survey.questions.to_a
          question = survey.questions.build(
            display_order: 1,
            short_text: QUESTION_SHORT_TEXT,
            text: "Would you like to use Advanced Security on private repositories?",
          )
          question.save! unless dry_run

          yes_choice = question.choices.build(short_text: "Yes", text: "Yes", display_order: 0)
          yes_choice.save! if !dry_run

          no_choice = question.choices.build(short_text: "No", text: "No", display_order: 1)
          no_choice.save! if !dry_run

          # Shift display order for all previous questions
          previous_questions.each do |question|
            question.update(display_order: T.must(question.display_order) + 1) unless dry_run
          end

          log_message = "question #{question.short_text} with choices:\n\t#{question.choices.map(&:attributes).join("\n\t")}"
          if dry_run
            log "Would have saved #{log_message}"
          else
            log "Saved #{log_message}"
          end
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
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::AddPrivateRepositoryAdvancedSecuritySurveyQuestion.new(options)
  transition.run
end
