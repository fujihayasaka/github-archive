# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedSponsorsSearchResultComponent < ApplicationComponent
  extend T::Sig

  sig { params(list: Primer::Alpha::ActionList, sponsorship: Sponsorship, active: T::Boolean).void }
  def initialize(list:, sponsorship:, active:)
    @list = list
    @sponsorship = sponsorship
    @active = active
  end

  private

  sig { returns Primer::Alpha::ActionList }
  attr_reader :list

  sig { returns Sponsorship }
  attr_reader :sponsorship

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled?
  end

  sig { returns T::Boolean }
  def active?
    @active
  end
end
