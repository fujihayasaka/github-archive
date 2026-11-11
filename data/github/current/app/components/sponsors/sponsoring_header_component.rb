# typed: true
# frozen_string_literal: true

class Sponsors::SponsoringHeaderComponent < ApplicationComponent
  # paginated_sponsorships - a PaginatedCollection of Sponsorships
  # active_sponsoring_count - an Integer of the number of active sponsorships
  # inactive_sponsoring_count - an Integer of the number of inactive sponsorships
  # location - a Symbol indicating where the button is being rendered
  # user_or_org - the User or Organization who is sponsoring
  # viewer_can_manage_sponsorships - Boolean indicating if the current user can create and manage
  #                                  sponsorships for this user/organization
  def initialize(paginated_sponsorships:, active_sponsoring_count:, inactive_sponsoring_count:, location:, user_or_org:, viewer_can_manage_sponsorships:)
    @paginated_sponsorships = paginated_sponsorships
    @active_sponsoring_count = active_sponsoring_count
    @inactive_sponsoring_count = inactive_sponsoring_count
    @location = location
    @user_or_org = user_or_org
    @viewer_can_manage_sponsorships = viewer_can_manage_sponsorships
  end

  private

  attr_reader :paginated_sponsorships, :active_sponsoring_count, :inactive_sponsoring_count, :location, :user_or_org

  def viewer_can_manage_sponsorships?
    @viewer_can_manage_sponsorships
  end
end
