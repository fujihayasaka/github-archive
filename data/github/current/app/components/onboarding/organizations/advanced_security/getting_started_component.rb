# typed: strict
# frozen_string_literal: true

class Onboarding::Organizations::AdvancedSecurity::GettingStartedComponent < ApplicationComponent
  sig { params(unbundled: T::Boolean).void }
  def initialize(unbundled: false)
    super
    @unbundled = unbundled
  end

  sig { returns(T::Boolean) }
  def unbundled?
    @unbundled
  end
end
