# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20160607211429_per_seat_downgrade_survey.rb -v | tee -a /tmp/per_seat_downgrade_survey.log
#
module GitHub
  module Transitions
    class PerSeatDowngradeSurvey < LegacyTransition
      # dry_run - Don't save/change any data, just log changes
      #           (optional, default: false)
      #
      # Returns nothing.
      def perform(dry_run: false, verbose: false)
        log "Starting transition #{self.class.to_s.underscore}"

        survey = Survey.create \
          slug: "per_seat_org_downgrade",
          title: "Per-Seat Org Downgrade"

        generate_question(survey: survey,
          slug: "join",
          text: "Will you share why you are cancelling your plan?",
          choices: [
            "The price of the plan is too high.",
            "We're moving to GitHub Enterprise.",
            "We're consolidating our code/repositories on another platform.",
            "We're consolidating our code/repositories in a different GitHub Org.",
            "We're moving our code to a personal GitHub plan.",
            "We don't need private repositories right now.",
            "We accidentally upgraded to a paid plan (private repositories).",
            "This organization is inactive or no longer exists.",
            "This organization was set up accidentally.",
            "Other (please specify)",
          ])

        generate_question(survey: survey, slug: "organization_id", text: "", hidden: true)

        log "Finished #{self.class.to_s.underscore}."
      end

      def generate_question(survey:, slug:, text:, choices: [], hidden: false)
        question = SurveyQuestion.create \
          survey_id: survey.id,
          short_text: slug,
          hidden: hidden,
          text: text

        if hidden
          question.choices.create \
            short_text: "hidden",
            text: "Hidden question used to gather context"
        else
          choices.each do |choice|
            question.choices.create \
              short_text: choice,
              text: choice
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
    opts.on("-d", "--dry_run", "Don't save or update any data, just log changes") do
      options[:dry_run] = true
    end
    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  transition = GitHub::Transitions::PerSeatDowngradeSurvey.new
  transition.perform(options)
end
