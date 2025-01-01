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
#   $ gudo bin/safe-ruby lib/github/transitions/20220520131556_repos_survey_fix_typo.rb --verbose | tee -a /tmp/repos_survey_fix_typo.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220520131556_repos_survey_fix_typo.rb --verbose -w | tee -a /tmp/repos_survey_fix_typo.log
#
module GitHub
  module Transitions
    class ReposSurveyFixTypo < Transition
      SURVEY_SLUG = "repositories_survey"

      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        survey = Survey.find_by_slug(SURVEY_SLUG)
        if survey.nil?
          log "Survey with slug #{SURVEY_SLUG} doesn't exist, skipping transition."
          return
        end

        question = survey.questions.find_by(short_text: "general_satisfaction")
        if question.nil?
          log "Question `general_satisfaction` does not exist, skipping transition."
          return
        end

        Survey.transaction do
          choice = question.choices.find_by(text: "Very Satisfied")

          if choice.nil?
            log "Choice `Very satisfied` does not exist for question `general_satisfaction`, skipping transition."
            next
          end

          choice.update(text: "Very satisfied") unless dry_run
        end

        log "Done!"
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

  transition = GitHub::Transitions::ReposSurveyFixTypo.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::ReposSurveyFixTypo.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
