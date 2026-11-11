# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200316181412_add_organization_id_question_to_downgrade_survey.rb -v | tee -a /tmp/add_organization_id_question_to_downgrade_survey.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200316181412_add_organization_id_question_to_downgrade_survey.rb -v -w | tee -a /tmp/add_organization_id_question_to_downgrade_survey.log
#
module GitHub
  module Transitions
    class AddOrganizationIdQuestionToDowngradeSurvey < Transition

      # Returns nothing.
      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        Survey.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          if dry_run?
            log "dry_run == true - Not creating the organization_id question"
            return
          end

          survey = Survey.find_by(slug: "per_seat_org_downgrade_text_only")

          unless survey.present?
            log "Organization downgrade text-only survey is required and does NOT exist"
            return
          end

          if survey.questions.find_by(short_text: "organization_id")
            log "'organization_id' question already exist in the organization downgrade text-only survey"
            return
          end

          q = survey.questions.create!(
            text: "Organization ID",
            short_text: "organization_id",
            hidden: true,
          )

          q.choices.create!(text: "Other", short_text: "other")
        end
      end

    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{__FILE__} [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::AddOrganizationIdQuestionToDowngradeSurvey.new(options)
  transition.run
end
