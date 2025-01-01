# typed: strict
# frozen_string_literal: true

class Sponsors::Orgs::PastSponsorshipLabelComponent < ApplicationComponent
  sig { params(sponsorship: Sponsorship, system_arguments: Primer::SystemArgumentsValue).void }
  def initialize(sponsorship:, **system_arguments)
    @sponsorship = sponsorship
    @system_arguments = system_arguments
    @system_arguments[:scheme] ||= :secondary
    @system_arguments[:test_selector] ||= "past-sponsorship-label"
  end

  sig { returns(String) }
  def call
    render(Primer::Beta::Label.new(**@system_arguments).with_content("Past sponsorship"))
  end

  private

  sig { returns(T::Boolean) }
  def render?
    !@sponsorship.active?
  end
end
