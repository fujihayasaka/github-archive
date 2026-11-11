# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200124160135_add_per_seat_org_downgrade_text_only_survey.rb -v | tee -a /tmp/add_per_seat_org_downgrade_text_only_survey.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200124160135_add_per_seat_org_downgrade_text_only_survey.rb -v -w | tee -a /tmp/add_per_seat_org_downgrade_text_only_survey.log
#
module GitHub
  module Transitions
    class AddPerSeatOrgDowngradeTextOnlySurvey < Transition

      # Returns nothing.
      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        Survey.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          if dry_run?
            log "dry_run == true - Not creating a per-seat org downgrade text-only survey"
            return
          end

          if Survey.find_by_slug("per_seat_org_downgrade_text_only")
            log "'per_seat_org_downgrade_text_only' survey already exists, skipping transition."
            return
          end

          survey = Survey.create!(
            title: "Per-Seat Org Downgrade Text-Only",
            slug: "per_seat_org_downgrade_text_only",
          )

          question = survey.questions.create!(
            text: "If you've got time to share, we'd love to learn more about why you're downgrading.",
            short_text: "downgrade_reason",
            display_order: 1,
          )

          question.choices.create!(text: "Other", short_text: "other", active: true)

          question = survey.questions.create!(
            text: "GitHub can reach out to me regarding my response",
            short_text: "contact_opt_in",
            display_order: 2,
          )

          question.choices.create([
            { text: "Yes", short_text: "yes", active: true, display_order: 1 },
            { text: "No", short_text: "no", active: true, display_order: 2 },
          ])

          log "'Per-Seat Org Downgrade Text-Only' survey, questions and choices created"
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

  transition = GitHub::Transitions::AddPerSeatOrgDowngradeTextOnlySurvey.new(options)
  transition.run
end
