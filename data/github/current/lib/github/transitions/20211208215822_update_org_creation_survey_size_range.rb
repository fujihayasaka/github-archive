# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20211208215822_update_org_creation_survey_size_range.rb --verbose | tee -a /tmp/update_org_creation_survey_range.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20211208215822_update_org_creation_survey_size_range.rb --verbose -w | tee -a /tmp/update_org_creation_survey_range.log
#
module GitHub
  module Transitions
    class UpdateOrgCreationSurveySizeRange < Transition
      SURVEY_SLUG = "org_creation"

      # Returns nothing.
      def perform
        log "Starting transition #{self.class.to_s.underscore}"
        if dry_run?
          log "dry_run == true - Not updating org creation survey with new questions"
          return
        end

        survey = Survey.find_by_slug(SURVEY_SLUG)

        unless survey.present?
          log "Org survey is required and does NOT exist"
          return
        end

        org_size_question = survey.questions.find_by(short_text: "org_size")

        unless org_size_question.present?
          log "Org size question is required and does NOT exist"
          return
        end

        # Hide old choices
        org_size_question.choices.update_all(active: false)

        org_size_question.choices.create!(text: "0", short_text: "org_size_0", display_order: 0)
        org_size_question.choices.create!(text: "1-5", short_text: "org_size_1_to_5", display_order: 1)
        org_size_question.choices.create!(text: "6-15", short_text: "org_size_6_to_15", display_order: 2)
        org_size_question.choices.create!(text: "16-24", short_text: "org_size_16_to_24", display_order: 3)
        org_size_question.choices.create!(text: "25+", short_text: "org_size_25_plus", display_order: 4)

        log "org_size_question updated"
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

    opts.on("-n", "--workers", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::UpdateOrgCreationSurveySizeRange.new(**options)
  transition.run
end
