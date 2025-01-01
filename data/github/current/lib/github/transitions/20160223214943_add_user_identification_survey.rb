# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20160223214943_add_user_identification_survey.rb | tee -a /tmp/add_user_identification_survey.log
#
module GitHub
  module Transitions
    class AddUserIdentificationSurvey < LegacyTransition
      # dry_run - Don't save/change any data, just log changes
      #           (optional, default: false)
      #
      # Returns nothing.
      def perform(dry_run: false)
        log "Starting transition #{self.class.to_s.underscore}"

        Survey.throttle do
          if Survey.find_by_slug("user_identification")
            log "Survey already exists, skipping transition."
            return
          end

          survey = Survey.create!(
            title: "User Identification",
            slug: "user_identification",
          )

          q = survey.questions.create!(
            text: "How would you describe your level of programming experience?",
            short_text: "programming_experience",
            display_order: 1,
          )
          q.choices.create(text: "Totally new to programming", short_text: "new")
          q.choices.create(text: "Somewhat experienced", short_text: "moderate")
          q.choices.create(text: "Very experienced", short_text: "very")

          q = survey.questions.create!(
            text: "What do you plan to use GitHub for?",
            short_text: "planned_uses",
            display_order: 2,
          )
          q.choices.create(text: "Development", short_text: "development")
          q.choices.create(text: "Design", short_text: "design")
          q.choices.create(text: "Project Management", short_text: "project_management")
          q.choices.create(text: "Research", short_text: "research")
          q.choices.create(text: "School projects", short_text: "school_projects")
          q.choices.create(text: "Other (please specify)", short_text: "other")

          q = survey.questions.create!(
            text: "Which is closest to how you would describe yourself?",
            short_text: "job_role",
            display_order: 3,
          )
          q.choices.create(text: "I'm a professional", short_text: "professional")
          q.choices.create(text: "I'm a hobbyist", short_text: "hobbyist")
          q.choices.create(text: "I'm a student", short_text: "student")
          q.choices.create(text: "Other (please specify)", short_text: "other")

          q = survey.questions.create!(
            text: "What are you interested in?",
            short_text: "interests",
            display_order: 4,
          )
          q.choices.create(text: "Other", short_text: "other")
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
  end.parse!

  transition = GitHub::Transitions::AddUserIdentificationSurvey.new
  transition.perform(options)
end
