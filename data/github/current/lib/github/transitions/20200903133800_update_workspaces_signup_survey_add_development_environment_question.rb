# typed: false
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200903133800_update_workspaces_signup_survey_add_development_environment_question.rb --verbose | tee -a /tmp/update_workspaces_signup_survey_add_development_environment_question.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20200903133800_update_workspaces_signup_survey_add_development_environment_question.rb --verbose -w | tee -a /tmp/update_workspaces_signup_survey_add_development_environment_question.log
#
module GitHub
  module Transitions
    class UpdateWorkspacesSignupsSurveyAddDevelopmentEnvironmentQuestion < Transition

      SURVEY_SLUG = "workspaces"
      QUESTION_SHORT_TEXT = "development_environments"

      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        survey = Survey.find_by(slug: SURVEY_SLUG)
        question = survey.questions.find_by(short_text: QUESTION_SHORT_TEXT)

        if question.present?
          log "'#{QUESTION_SHORT_TEXT}' question already exists in '#{SURVEY_SLUG}' survey, skipping transition."
          return
        end

        generate_question(
          survey: survey,
          short_text: QUESTION_SHORT_TEXT,
          text: "Which of these development environments do you use?",
          choices: [
            "Android Studio",
            "Atom",
            "Eclipse",
            "IntelliJ IDEA",
            "Jupyter / IPython",
            "Notepad++",
            "PyCharm",
            "Sublime Text",
            "Vim",
            "Visual Studio",
            "Visual Studio Code",
            "Xcode",
            "Other"
          ],
        )

        log "Done!"
      end

      def generate_question(survey:, short_text:, text:, choices: [])
        question = survey.questions.build(
          display_order: survey.questions.count + 1,
          short_text: short_text,
          text: text,
        )

        question.save! unless dry_run

        if choices.length == 0
          # Add one dummy choice to satisfy the validation for survey answers at runtime
          choice = question.choices.build(short_text: "other", text: "other", display_order: 0)

          if !dry_run
            choice.save!
          end
        else
          choices.each_with_index do |choice, i|
            choice = question.choices.build(short_text: choice, text: choice, display_order: i)

            if !dry_run
              choice.save!
            end
          end
        end

        log_message = "question #{question.short_text} with choices:\n\t#{question.choices.map(&:attributes).join("\n\t")}"
        if dry_run
          log "Would have saved " + log_message
        else
          log "Saved " + log_message
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

  transition = GitHub::Transitions::UpdateWorkspacesSignupsSurveyAddDevelopmentEnvironmentQuestion.new(options)
  transition.run
end
