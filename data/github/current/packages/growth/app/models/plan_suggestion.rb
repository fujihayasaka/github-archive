# typed: true
# frozen_string_literal: true

# PlanSuggestion is used in the Welcome flow to suggest a plan to
# customer based on their team size and purpose.
class PlanSuggestion
  TEAM_SIZE_TO_DISCUSS_PLAN = "50+"
  SINGLE_PERSON_TEAM_SIZE   = "1"
  EDUCATION_PLANS = {
    education_student: :education_student,
    education_teacher: :education_teacher,
  }.freeze

  attr_reader :team_size, :user_self_description, :purpose

  # @param team_size [String] the string representing the range of the
  #                           team size
  # @param user_self_description [String] the user's self description
  def initialize(user:, team_size:, user_self_description: nil, purpose: [])
    @team_size             = team_size
    @user                  = user
    @user_self_description = user_self_description&.to_sym
    @purpose               = purpose
  end

  # Returns the recommended plan based on customer needs.
  #
  # @return [Symbol] the recommended plan:
  #         - {:education_student}
  #         - {:education_teacher}
  #         - {:business}
  #         - {:business_plus}
  #         - {:free}
  def recommended_plan
    return education_plan if education_plan.present?
    return :free if single_person?

    must_discuss_plan? ? :business_plus : :business
  end

  # Checks if customer must discuss their plan needs.
  #
  # @return [Boolean]
  def must_discuss_plan?
    @team_size == TEAM_SIZE_TO_DISCUSS_PLAN
  end

  # Checks if plan is for a single person.
  #
  # @return [Boolean]
  def single_person?
    @team_size == SINGLE_PERSON_TEAM_SIZE
  end

  def recommend_plan
    GlobalInstrumenter.instrument("recommended_plan.recommended", {
      user: @user,
      plan_suggestion: self,
    })

    self
  end

  private

  def education_plan
    EDUCATION_PLANS.fetch(@user_self_description, nil)
  end
end
