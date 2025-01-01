# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200519233106_update_org_creation_survey.rb --verbose | tee -a /tmp/update_org_creation_survey.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200519233106_update_org_creation_survey.rb --verbose -w | tee -a /tmp/update_org_creation_survey.log
#
module GitHub
  module Transitions
    class UpdateOrgCreationSurvey < Transition

      # Returns nothing.
      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        Survey.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          if dry_run?
            log "dry_run == true - Not updating org creation survey with new questions"
            return
          end

          survey = Survey.find_by_slug("org_creation")

          unless survey.present?
            log "Org survey is required and does NOT exist"
            return
          end

          # Hide old questions
          survey.questions.update_all(hidden: true)
          log "old questions hidden"

          # Create new questions
          org_creator_role_question = survey.questions.create!(
            text: "What do you spend time on most day-to-day?",
            short_text: "org_creator_role",
            display_order: 0,
          )
          org_creator_role_question.choices.create!(text: "Writing code", short_text: "org_creator_role_coding", display_order: 0)
          org_creator_role_question.choices.create!(text: "Managing and coordinating engineering work", short_text: "org_creator_role_managing", display_order: 1)
          org_creator_role_question.choices.create!(text: "Planning projects", short_text: "org_creator_role_planning", display_order: 2)
          org_creator_role_question.choices.create!(text: "Billing administration", short_text: "org_creator_role_billing", display_order: 3)
          org_creator_role_question.choices.create!(text: "Other", short_text: "org_creator_role_other", display_order: 4)

          log "org_creator_role_question created"

          org_size_question = survey.questions.find_by(short_text: "org_size")

          org_size_question.update(
            text: "How many people do you expect to actively work within this GitHub organization?",
            display_order: 1,
            hidden: false
          )
          # Hide old choices
          org_size_question.choices.update_all(active: false)

          org_size_question.choices.create!(text: "0", short_text: "org_size_0", display_order: 0)
          org_size_question.choices.create!(text: "1-5", short_text: "org_size_1_to_5", display_order: 1)
          org_size_question.choices.create!(text: "6-15", short_text: "org_size_6_to_15", display_order: 2)
          org_size_question.choices.create!(text: "25+", short_text: "org_size_25_plus", display_order: 3)

          log "org_size_question updated"

          org_purpose_question = survey.questions.create!(
            text: "What type of work do you plan to use this organization for?",
            short_text: "org_purpose",
            display_order: 2,
          )
          org_purpose_question.choices.create!(text: "Open source projects", short_text: "org_purpose_open_source", display_order: 0)
          org_purpose_question.choices.create!(text: "Education projects", short_text: "org_purpose_education", display_order: 1)
          org_purpose_question.choices.create!(text: "Personal projects", short_text: "org_purpose_personal", display_order: 2)
          org_purpose_question.choices.create!(text: "Work projects", short_text: "org_purpose_work", display_order: 3)
          org_purpose_question.choices.create!(text: "Other", short_text: "org_purpose_other", display_order: 4)

          log "org_purpose_question created"

          org_next_seven_days_question = survey.questions.create!(
            text: "What do you expect to do on GitHub in the next seven days?",
            short_text: "org_next_seven_days",
            display_order: 3,
          )
          org_next_seven_days_question.choices.create!(text: "Manage code", short_text: "org_next_seven_days_manage_code", display_order: 0)
          org_next_seven_days_question.choices.create!(text: "Collaborate on code", short_text: "org_next_seven_days_collaborate_code", display_order: 1)
          org_next_seven_days_question.choices.create!(text: "Plan and track work", short_text: "org_next_seven_days_plan", display_order: 2)
          org_next_seven_days_question.choices.create!(text: "Set up CI/CD", short_text: "org_next_seven_days_ci_cd", display_order: 3)
          org_next_seven_days_question.choices.create!(text: "Improve security", short_text: "org_next_seven_days_security", display_order: 4)
          org_next_seven_days_question.choices.create!(text: "Other", short_text: "org_next_seven_days_other", display_order: 5)

          log "org_next_seven_days_question created"

          org_existing_repository_question = survey.questions.create!(
            text: "Do you have an existing repository for your project?",
            short_text: "org_existing_repository",
            display_order: 4,
          )
          org_existing_repository_question.choices.create!(text: "Yes", short_text: "org_existing_repository_yes", display_order: 0)
          org_existing_repository_question.choices.create!(text: "No", short_text: "org_existing_repository_no", display_order: 1)

          log "org_existing_repository_question created"

          org_existing_repo_source_question = survey.questions.create!(
            text: "Where was your existing repository previously hosted? ",
            short_text: "org_existing_repo_source",
            display_order: 5,
          )
          org_existing_repo_source_question.choices.create!(text: "GitHub", short_text: "org_existing_repo_source_github", display_order: 0)
          org_existing_repo_source_question.choices.create!(text: "GitLab", short_text: "org_existing_repo_source_gitlab", display_order: 1)
          org_existing_repo_source_question.choices.create!(text: "Bitbucket", short_text: "org_existing_repo_source_bitbucket", display_order: 2)
          org_existing_repo_source_question.choices.create!(text: "SourceForge", short_text: "org_existing_repo_source_sourceforge", display_order: 3)
          org_existing_repo_source_question.choices.create!(text: "Local storage", short_text: "org_existing_repo_source_local_storage", display_order: 4)
          org_existing_repo_source_question.choices.create!(text: "Other", short_text: "org_existing_repo_source_other", display_order: 5)

          log "org_existing_repo_source_question created"
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::UpdateOrgCreationSurvey.new(options)
  transition.run
end
