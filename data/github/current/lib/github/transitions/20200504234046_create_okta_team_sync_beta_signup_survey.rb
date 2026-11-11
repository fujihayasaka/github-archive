# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# This transition just creates the mandatory (and question-less) Survey for Okta
# Team Sync's Early Access Program. It's just a single line on the database, so
# no throttling/read replicas/etc were involved.
#
# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200504234046_create_okta_team_sync_beta_signup_survey.rb --verbose | tee -a /tmp/create_okta_team_sync_beta_signup_survey.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200504234046_create_okta_team_sync_beta_signup_survey.rb --verbose -w | tee -a /tmp/create_okta_team_sync_beta_signup_survey.log
#
module GitHub
  module Transitions
    class CreateOktaTeamSyncBetaSignupSurvey < Transition
      SURVEY_SLUG = "okta_team_sync"

      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        if Survey.exists?(slug: SURVEY_SLUG)
          log "Survey with slug #{SURVEY_SLUG} already exists, skipping transition."
          return
        end

        Survey.transaction do
          survey = Survey.new(
            title: SURVEY_SLUG.titleize,
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
    opts.banner = "Usage: ruby lib/github/transitions/20200504234046_create_okta_team_sync_beta_signup_survey.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("-h", "--help", "Prints this help") do
      puts opts
      exit
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CreateOktaTeamSyncBetaSignupSurvey.new(options)
  transition.run
end
