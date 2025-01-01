# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# ***NOTE***
# This file has been modified since it was originally run due to adding Sorbet type-checking
# to all Codespace-owned files in the dotcom. To see this file as it was originally run, see this commit:
# https://github.com/github/github/blob/dca0577c1daa58ffe25fb7941e001709ef451ebc/lib/github/transitions/20200428140122_update_workspaces_signup_survey_choices.rb

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200428140122_update_workspaces_signup_survey_choices.rb --verbose | tee -a /tmp/update_workspaces_signup_survey_choices.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200428140122_update_workspaces_signup_survey_choices.rb --verbose -w | tee -a /tmp/update_workspaces_signup_survey_choices.log
#
module GitHub
  module Transitions
    class UpdateWorkspacesSignupSurveyChoices < Transition

      SURVEY_SLUG = "workspaces"

      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        survey = Survey.find_by(slug: SURVEY_SLUG)

        question = survey&.questions&.find_by(short_text: "programming_languages")
        js_choice = question&.choices&.find_by(short_text: "JavaScript/TypeScript/Node.js")
        js_choice&.text = js_choice.short_text = "JavaScript / TS"

        other_choice = question&.choices&.find_by(short_text: "Other(s)")
        other_choice&.text = other_choice.short_text = "Other"

        if dry_run
          log "Would have saved survey \"#{survey&.slug}\" with updated choices:"
          log "JS question: #{js_choice&.attributes}"
          log "Other question: #{other_choice&.attributes}"
        else
          js_choice&.save!
          other_choice&.save!

          log "Saved survey \"#{survey&.slug}\" with updated choices."
          log "JS question: #{js_choice&.attributes}"
          log "Other question: #{other_choice&.attributes}"
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
    opts.banner = "Usage: ruby #{__FILE__} [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::UpdateWorkspacesSignupSurveyChoices.new(options)
  transition.run
end
