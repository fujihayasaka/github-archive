# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200903140700_update_workspaces_signup_survey_reorder_choices.rb --verbose | tee -a /tmp/update_workspaces_signup_survey_reorder_choices.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200903140700_update_workspaces_signup_survey_reorder_choices.rb --verbose -w | tee -a /tmp/update_workspaces_signup_survey_reorder_choices.log
#
module GitHub
  module Transitions
    class UpdateWorkspacesSignupsSurveyReorderChoices < Transition

      SURVEY_SLUG = "workspaces"

      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        survey = Survey.find_by(slug: SURVEY_SLUG)
        question = survey.questions.find_by(short_text: "programming_languages")
        reordered_choices = [
          "JavaScript / TS",
          "Python",
          "Java",
          "C#",
          "PHP",
          "Ruby",
          "Swift",
          "C/C++",
          "Dart",
          "Go",
          "Kotlin",
          "Rust",
          "Other",
        ]
        reordered_choices.each.with_index do |short_text, index|
          choice = question.choices.find_by(short_text: short_text)
          if choice.blank? || choice[:display_order] == index
            log "Skipped '#{short_text}' choice"
            next
          end
          if dry_run
            log "Would have reordered '#{short_text}' choice from position '#{choice.display_order}' to position '#{index}'"
          else
            choice.display_order = index
            choice.save!
            log "Reordered '#{short_text}' choice from position '#{choice.display_order}' to position '#{index}'"
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
    opts.banner = "Usage: ruby #{__FILE__} [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::UpdateWorkspacesSignupsSurveyReorderChoices.new(options)
  transition.run
end
