# typed: true
# frozen_string_literal: true

class Sponsors::Profile::SponsorsOnlyRepoInvitationComponent < ApplicationComponent
  def initialize(sponsorship:)
    @sponsorship = sponsorship
  end

  private

  attr_reader :sponsorship

  delegate :sponsorable, to: :sponsorship

  def render?
    sponsorship&.active? && repository
  end

  memoize def repository
    sponsorship.sponsors_only_repository
  end
end
