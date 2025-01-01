# typed: true
# frozen_string_literal: true

# PlanSuggestion is used in the Welcome flow to suggest a plan to
# customer based on their team size and tools they use.
class PlanSuggestion
  TEAM_SIZE_TO_DISCUSS_PLAN = "50+"
  SINGLE_PERSON_TEAM_SIZE   = "1"
  TOOL_BUSINESS_PLUS_ONLY   = "enterprise_security"
  EDUCATION_PLANS = {
    education_student: :education_student,
    education_teacher: :education_teacher,
  }.freeze

  attr_reader :education_type, :team_size, :tools, :user_self_description

  # @param team_size [String] the string representing the range of the
  #                           team size
  # @param education_type [#to_sym] the educational type of user.
  #                                 :education_student, :education_teacher, :eduction_na. nil otherwise.
  # @param tools [Array] a collection of tools they use
  # @param user_self_description [String] the user's self description
  def initialize(user:, team_size:, education_type: nil, tools: [], user_self_description: nil)
    @education_type = education_type&.to_sym
    @team_size      = team_size
    @tools          = tools
    @user           = user
    @user_self_description = user_self_description&.to_sym
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

    business_plus_plan? ? :business_plus : :business
  end

  # Checks if customer muss discuss their plan needs.
  #
  # @return [Boolean]
  def must_discuss_plan?
    @team_size == TEAM_SIZE_TO_DISCUSS_PLAN
  end

  # Checks if plan is for a single person.
  #
  # @return [Boolean]
  def single_person?
    @team_size == SINGLE_PERSON_TEAM_SIZE && !@tools.include?(TOOL_BUSINESS_PLUS_ONLY)
  end

  def recommend_plan
    GlobalInstrumenter.instrument("recommended_plan.recommended", {
      user: @user,
      plan_suggestion: self,
    })

    self
  end

  private

  def business_plus_plan?
    @tools.include?(TOOL_BUSINESS_PLUS_ONLY) || must_discuss_plan?
  end

  def education_type_or_self_description
    @education_type || @user_self_description
  end

  def education_plan
    EDUCATION_PLANS.fetch(education_type_or_self_description, nil)
  end
end
