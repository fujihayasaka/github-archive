# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20210601190848_create_projects_v_next_survey.rb --verbose | tee -a /tmp/create_projects_v_next_survey.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20210601190848_create_projects_v_next_survey.rb --verbose -w | tee -a /tmp/create_projects_v_next_survey.log
#
module GitHub
  module Transitions
    class CreateProjectsVNextSurvey < Transition

      SURVEY_SLUG = "projects_vnext"

      # @github/db-schema-reviewers is your friend, and can help code review
      # transitions before they're run to make sure they're being nice to our
      # database clusters. We're usually looking for a few things in transitions:
      #   1. Iterators: We want to query the database for records to change in batches
      #   2. Read-Only Replicas: If we're reading data to be changed, we want to do it on
      #      the read-only replicas to keep load off the master
      #   3. Throttle writes: We want to make sure we wrap any actual writes to the master
      #      in a `throttle_with_retry` block, which should be called on the most specific
      #      `ApplicationRecord::*` class/subclass or object. This will make sure we don't
      #      overwhelm master and cause replication lag.
      #   4. Efficient queries: We want to avoid massive table scans, so make sure your
      #      query has an index or is performant and safe without one.
      #
      #   For more information on all this, checkout the transition docs at
      #   https://thehub.github.com/engineering/development-and-ops/dotcom/migrations-and-transitions/transitions/

      def perform
        readonly do
          log "Starting transition #{self.class.to_s.underscore}"

          if Survey.exists?(slug: SURVEY_SLUG)
            log "Survey with slug #{SURVEY_SLUG} already exists, skipping transition."
            return
          end

          if !dry_run
            ActiveRecord::Base.connected_to(role: :writing) do
              create_survey
            end
          else
            create_survey
          end
        end
      end

      private

      def create_survey
        Survey.transaction do
          survey = Survey.new(
            title: "Projects vNext",
            slug: SURVEY_SLUG,
          )

          if dry_run
            log "Would have saved survey \"#{survey.slug}\" with #{survey.attributes}."
          else
            survey.save!
            log "Saved survey \"#{survey.slug}\" with #{survey.attributes}."
          end
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
    opts.banner = "Usage: ruby lib/github/transitions/20210601190848_create_projects_v_next_survey.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CreateProjectsVNextSurvey.new(**options)
  transition.run
end
