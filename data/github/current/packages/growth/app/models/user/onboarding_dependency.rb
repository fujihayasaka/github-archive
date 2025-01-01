# typed: strict
# frozen_string_literal: true

module User::OnboardingDependency
  extend T::Sig

  BEGINNER_ANSWERS = T.let([
    "None—I don't program at all",
    "New to programming",
  ], T::Array[String])

  INTERMEDIATE_ANSWERS = T.let([
    "Somewhat experienced",
    "Very experienced",
  ], T::Array[String])

  # Onboarding milestones for users.
  sig { returns(T::Boolean) }
  def beginner_level_experience?
    programming_experience.in?(BEGINNER_ANSWERS)
  end

  sig { returns(T::Boolean) }
  def intermediate_level_experience?
    programming_experience.in?(INTERMEDIATE_ANSWERS)
  end

  sig { returns(T.nilable(String)) }
  def programming_experience
    T.bind(self, User)
    return unless Onboarding.for(self).answered_user_identification_questions?

    SurveyQuestion.find_by(short_text: "level_of_experience")&.tap do |question|
      SurveyAnswer.for(self).find_by(question: question)&.tap do |answer|
        return answer.choice&.text
      end
    end
    nil
  end
end
