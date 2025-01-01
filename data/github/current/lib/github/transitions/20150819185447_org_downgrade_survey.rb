# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20150819185447_org_downgrade_survey.rb | tee -a /tmp/org_downgrade_survey.log
#
module GitHub
  module Transitions
    class OrgExitSurvey < LegacyTransition
      # dry_run - Don't save/change any data, just log changes
      #           (optional, default: false)
      #
      # Returns nothing.
      def perform(dry_run: false, force: false)
        log "Starting transition #{self.class.to_s.underscore}"

        @force = force

        survey = Survey.find_or_initialize_by(slug: "org_downgrade")
        survey.title = "Org Downgrade Survey"
        survey.save!

        # Question 1:
        generate_question(survey: survey,
          slug: "join",
          text: "Will you share why you are changing GitHub plans?",
          choices: [
            "The price of this plan is too high.",
            "The size of this plan is too big, we don't need all the repositories.",
            "We are moving to GitHub Enterprise.",
            "We are consolidating repositories on another platform.",
            "We are changing into an open source project.",
            "This organization isn't active at this time.",
            "I accidentally set this organization up and don’t need it.",
            "Other (please specify)",
          ])

        # Hidden questions for survey context.  We create a single SurveyChoice
        # as a SurveyAnswer validates presence of a SurveyChoice.
        generate_question(survey: survey, slug: "organization_id", text: "", hidden: true)
        generate_question(survey: survey, slug: "from_plan", text: "", hidden: true)
        generate_question(survey: survey, slug: "to_plan", text: "", hidden: true)
      end

      def generate_question(survey:, slug:, text:, choices: [], hidden: false)
        question = SurveyQuestion.find_or_initialize_by(survey_id: survey.id, short_text: slug)
        question.hidden = hidden
        question.text = text
        question.save!

        reset_question(question)

        if hidden
          # Add a single SurveyChoice to satisfy the presence validation of
          # a SurveyChoice when constructing a SurveyAnswer.
          question.choices.create(short_text: "hidden", text: "Hidden question used to gather context")
        else
          choices.each do |choice|
            choice = question.choices.build(short_text: choice, text: choice)
            choice.save!
          end
        end
      end

      def reset_question(question)
        if question.answers.count > 0 && !@force
          raise "Survey question '#{question.text}' already has answers. Use --force to blow them away."
        end

        question.choices.clear
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-d", "--dry_run", "Don't save or update any data, just log changes") do
      options[:dry_run] = true
    end
    opts.on("-f", "--force", "Force question update") do
      options[:force] = true
    end
  end.parse!

  transition = GitHub::Transitions::OrgExitSurvey.new
  transition.perform(options)
end
