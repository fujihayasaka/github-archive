# typed: strict
# frozen_string_literal: true

class Onboarding::Organizations::AdvancedSecurity::TrialSurveyBannerComponent < ApplicationComponent
  extend T::Sig

  SURVEY_LINK = "https://survey3.medallia.com/?ZYVc7H-0Ppp4sWzCTpyEvd"

  sig { returns Organization }
  attr_reader :organization

  sig { returns User }
  attr_reader :user

  sig { returns T::Boolean }
  attr_reader :show_banner

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig do params(
    organization: Organization,
    user: User,
    show_banner: T.nilable(T::Boolean),
    system_arguments: T.untyped
  ).void
  end
  def initialize(organization:, user:, show_banner: false, **system_arguments)
    @organization = organization
    @user = user
    if show_banner.nil?
      @show_banner = false
    else
      @show_banner = T.let(show_banner, T::Boolean)
    end
    @system_arguments = system_arguments
  end

  sig { returns T::Boolean }
  def render?
    @show_banner
  end

  sig { returns String }
  def survey_link
    SURVEY_LINK
  end
end
