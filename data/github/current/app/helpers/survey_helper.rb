# typed: false
# frozen_string_literal: true

module SurveyHelper
  def hidden_question_input(survey, slug, value)
    question = survey.questions.hidden.where(short_text: slug).first
    if question
      hidden_field_tag("answers[][question_id]", question.id, id: nil) + \
      hidden_field_tag("answers[][choice_id]", question.choices.first.id, id: nil) + \
      hidden_field_tag("answers[][other_text]", value, id: nil)
    end
  end
end
