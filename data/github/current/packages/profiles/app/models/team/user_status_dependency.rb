# typed: false
# frozen_string_literal: true

module Team::UserStatusDependency
  # Public: Default number of team members to load the user status for.
  MEMBER_STATUS_FETCH_LIMIT = 1000

  # Public: Get a list of user statuses that belong to members of the team.
  #
  # order_by - an optional Hash for ordering the results; valid keys include:
  #   :field - valid values include "updated_at"
  #   :direction - valid values include "ASC" and "DESC"
  #
  # limit - an optional Integer for setting the maximum number of returned
  # results.
  #
  # Returns an Array of UserStatuses.
  def member_statuses(order_by: nil, viewer: nil, limit: MEMBER_STATUS_FETCH_LIMIT)
    statuses = []

    member_ids[0...limit].each_slice(100) do |user_ids|
      next_statuses = UserStatus.joins(:user).
        merge(User.filter_spam_for(viewer)).
        for_org_or_public(organization_id).
        where(user_id: user_ids).active
      statuses.concat(next_statuses)
    end

    order_by ||= {}
    field = order_by[:field] || "updated_at"
    direction = order_by[:direction] || "DESC"

    statuses = statuses.sort_by { |status| status.public_send(field) }
    statuses = statuses.reverse if direction == "DESC"
    statuses
  end
end
