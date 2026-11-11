# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::MeetTheTeamSearchResultComponent < ApplicationComponent
  sig { params(list: Primer::Alpha::ActionList, member: User, active: T::Boolean).void }
  def initialize(list:, member:, active:)
    @list = list
    @member = member
    @active = active
  end

  private

  sig { returns Primer::Alpha::ActionList }
  attr_reader :list

  sig { returns User }
  attr_reader :member

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled?
  end

  sig { returns T::Boolean }
  def active?
    @active
  end
end
