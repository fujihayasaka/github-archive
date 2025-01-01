# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::OrganizationOwnersListComponent < ApplicationComponent
  include AvatarHelper

  MAX_OWNERS_TO_DISPLAY = 10

  def initialize(sponsorable:)
    @sponsorable = sponsorable
  end

  private

  def render?
    @sponsorable.organization?
  end

  memoize def owners
    @sponsorable.admins
      .order(:login)
      .limit(MAX_OWNERS_TO_DISPLAY)
  end

  memoize def owners_total
    @sponsorable.admins.size
  end

  memoize def has_more_owners?
    owners_total > MAX_OWNERS_TO_DISPLAY
  end

  def organization_owners_link
    org_people_path(@sponsorable, query: "role:owner")
  end
end
