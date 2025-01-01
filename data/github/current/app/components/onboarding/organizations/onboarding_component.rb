# typed: true
# frozen_string_literal: true

class Onboarding::Organizations::OnboardingComponent < ApplicationComponent
  attr_reader :organization

  def initialize(organization:)
    @organization = organization
  end

  # @return [Boolean]
  def render?
    helpers.show_onboarding_component?(organization)
  end

  private

  attr_reader :trial
end
