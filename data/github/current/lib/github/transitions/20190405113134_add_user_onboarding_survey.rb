# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20190405113134_add_user_onboarding_survey.rb -v | tee -a /tmp/add_user_onboarding_survey.log
#
module GitHub
  module Transitions
    class AddUserOnboardingSurvey < Transition

      # This will override the previous transition for setting up the user
      # identification survey,
      # "20160223214943_add_user_identification_survey.rb"
      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        Survey.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          if dry_run?
            log "dry_run == true - Not creating a user onboarding survey"
            return
          end

          if Survey.find_by_slug("user_identification")
            log "Survey already exists, skipping transition."
            return
          end

          survey = Survey.create!(
            title: "User Identification",
            slug: "user_identification",
          )

          q = survey.questions.create!(
            text: "What is your level of programming experience?",
            short_text: "level_of_experience",
            display_order: 1,
          )
          q.choices.create!(text: "None—I don't program at all", short_text: "developer")
          q.choices.create!(text: "New to programming",          short_text: "researcher")
          q.choices.create!(text: "Somewhat experienced",        short_text: "student")
          q.choices.create!(text: "Very experienced",            short_text: "project_manager")

          q = survey.questions.create!(
            text: "What do you plan to use GitHub for?",
            short_text: "github_plans",
            display_order: 2,
          )
          q.choices.create!(text: "Learning to code",                     short_text: "learn_coding")
          q.choices.create!(text: "Learning Git and GitHub",              short_text: "learn_github")
          q.choices.create!(text: "Host a project (repository)",          short_text: "host_project")
          q.choices.create!(text: "Creating a website with GitHub Pages", short_text: "github_pages")
          q.choices.create!(text: "Collaborating with my team",           short_text: "team_collaborate")
          q.choices.create!(text: "Finding a project to contribute to",   short_text: "contribute")
          q.choices.create!(text: "School work / School-related project", short_text: "school_work")
          q.choices.create!(text: "The GitHub API",                       short_text: "github_api")
          q.choices.create!(text: "I don't know yet",                     short_text: "do_not_know_yet")
          q.choices.create!(text: "Other (please specify)",               short_text: "other")

          q = survey.questions.create!(
            text: "What are you interested in?",
            short_text: "interests",
            display_order: 3,
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
    opts.banner = "Usage: add_user_onboarding_survey.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::AddUserOnboardingSurvey.new(options)
  transition.run
end
