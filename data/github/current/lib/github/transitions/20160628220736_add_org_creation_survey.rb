# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20160628220736_add_org_creation_survey.rb -v | tee -a /tmp/add_org_creation_survey.log
#
module GitHub
  module Transitions
    class AddOrgCreationSurvey < LegacyTransition
      # Returns nothing.
      def perform(verbose: false)
        log "Starting transition #{self.class.to_s.underscore}"

        Survey.throttle do
          if Survey.find_by_slug("org_creation")
            log "Survey already exists, skipping transition."
            return
          end

          survey = Survey.create!(
            title: "Org Creation",
            slug: "org_creation",
          )

          q = survey.questions.create!(
            text: "What do you plan to use your organization for?",
            short_text: "planned_use",
            display_order: 1,
          )
          q.choices.create(text: "Professional work, for-profit", short_text: "for_profit", display_order: 1)
          q.choices.create(text: "Professional work, non-profit (not including educational programs)", short_text: "non_profit", display_order: 2)
          q.choices.create(text: "An educational program", short_text: "educational", display_order: 3)
          q.choices.create(text: "An open source project", short_text: "open_source", display_order: 4)
          q.choices.create(text: "A hackathon", short_text: "hackathon", display_order: 5)
          q.choices.create(text: "I'm not sure yet", short_text: "not_sure", display_order: 6)
          q.choices.create(text: "Other (please describe)", short_text: "other", display_order: 7)

          q = survey.questions.create!(
            text: "How long do you plan to use this organization?",
            short_text: "use_duration",
            display_order: 2,
          )
          q.choices.create(text: "Just a few days", short_text: "short-term", display_order: 1)
          q.choices.create(text: "A few weeks to months", short_text: "moderate-term", display_order: 2)
          q.choices.create(text: "A year or more", short_text: "long-term", display_order: 3)
          q.choices.create(text: "I'm not sure yet", short_text: "unsure", display_order: 4)
          q.choices.create(text: "Other (please describe)", short_text: "other", display_order: 5)

          q = survey.questions.create!(
            text: "About how many people do you expect to work with in this organization?",
            short_text: "org_size",
            display_order: 3,
          )
          q.choices.create(text: "I plan to work alone", short_text: "alone", display_order: 1)
          q.choices.create(text: "5 or fewer", short_text: "5_or_fewer", display_order: 2)
          q.choices.create(text: "6 to 20", short_text: "6_to_20", display_order: 3)
          q.choices.create(text: "21 to 50", short_text: "21_to_50", display_order: 4)
          q.choices.create(text: "More than 50", short_text: "more_than_50", display_order: 5)
          q.choices.create(text: "I'm not sure yet", short_text: "unsure", display_order: 6)
          q.choices.create(text: "Other (please describe)", short_text: "other", display_order: 7)
        end

        log "Finished #{self.class.to_s.underscore}"
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  transition = GitHub::Transitions::AddOrgCreationSurvey.new
  transition.perform(options)
end
