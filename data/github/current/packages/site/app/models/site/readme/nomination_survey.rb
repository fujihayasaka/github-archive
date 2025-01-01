# typed: true
# frozen_string_literal: true

class Site::Readme::NominationSurvey
  SLUG = "nominate_maintainer"

  QUESTION_NAMES = %w(
    nominator_user_id
    nominee_login
    nominee_name
    nominee_project
    nominee_reason
    nominee_role
  )

  NOMINEE_ROLE_CHOICES = %w(
    developer
    open_source_contributor
    open_source_maintainer
    open_source_team
  )

  def self.survey
    Survey.preload(questions: :choices).find_by(slug: SLUG)
  end

  def self.create!(dry_run: true)
    survey = Survey.new(
      title: SLUG.titleize,
      slug: SLUG,
    )

    QUESTION_NAMES.each_with_index do |question_name, index|
      question = survey.questions.build(
        display_order: index + 1,
        short_text: question_name,
        text: question_name.titleize,
      )

      if question_name == "nominee_role"
        NOMINEE_ROLE_CHOICES.each do |nominee_role_choice|
          question.choices.build(
            question: question,
            short_text: nominee_role_choice,
            text: nominee_role_choice.titleize,
          )
        end
      else
        question.choices.build(
          question: question,
          short_text: question_name,
          text: question_name.titleize,
        )
      end
    end

    unless dry_run
      survey.save!
    end

    survey
  end
end
