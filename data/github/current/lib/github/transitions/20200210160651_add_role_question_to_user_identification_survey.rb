# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200210160651_add_role_question_to_user_identification_survey.rb -v | tee -a /tmp/add_role_question_to_user_identification_survey.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200210160651_add_role_question_to_user_identification_survey.rb -v -w | tee -a /tmp/add_role_question_to_user_identification_survey.log
#
module GitHub
  module Transitions
    class AddRoleQuestionToUserIdentificationSurvey < Transition

      # Returns nothing.
      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        Survey.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          if dry_run?
            log "dry_run == true - Not creating the role survey question"
            return
          end

          survey = Survey.find_by_slug("user_identification")

          unless survey.present?
            log "User identification survey is required and does NOT exist"
            return
          end

          if survey.questions.find_by_short_text("user_role")
            log "'user_role' question already exist in the user identification survey"
            return
          end

          q = survey.questions.create!(
            text: "What kind of work do you do, mainly?",
            short_text: "user_role",
            display_order: 0,
          )

          q.choices.create!(text: "Software Engineer",      short_text: "role_engineer")
          q.choices.create!(text: "Student",                short_text: "role_student")
          q.choices.create!(text: "Product Manager",        short_text: "role_product_manager")
          q.choices.create!(text: "UX & Design",            short_text: "role_ux_design")
          q.choices.create!(text: "Data & Analytics",       short_text: "role_data_analytics")
          q.choices.create!(text: "Marketing & Sales",      short_text: "role_marketing_sales")
          q.choices.create!(text: "Teacher",                short_text: "role_teacher")
          q.choices.create!(text: "Other",                  short_text: "role_other")

          # Increment the display_order values of this survey questions to start from 1
          SurveyQuestion.increment_counter(:display_order, survey.reload.questions.ids)
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

  transition = GitHub::Transitions::AddRoleQuestionToUserIdentificationSurvey.new(options)
  transition.run
end
