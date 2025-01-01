# typed: false
# frozen_string_literal: true

module ControllerMethods
  module AnswerParams
    private

    def answer_params(survey = @survey)
      permittable_answer = [:choice, { other: {} }, { selections: [] }, { choices: [] }]
      permittable_answers = survey.questions.to_a.map.with_object({}) { |q, h| h[q.id.to_s.to_sym] = permittable_answer }
      params.require(:answers).permit(permittable_answers).to_hash
    end
  end
end
