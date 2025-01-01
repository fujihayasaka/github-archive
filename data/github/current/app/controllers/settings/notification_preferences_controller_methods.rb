# typed: false
# frozen_string_literal: true

module Settings
  module NotificationPreferencesControllerMethods
    ORG_NOTIFICATION_ROUTING_PER_PAGE = 100

    def current_user_affiliated_organizations(page: current_page, per_page: org_routing_per_page)
      organization_ids = current_user.affiliated_organizations.pluck(:id)
      organizations = ::Organization.
        includes(:business).
        where(id: organization_ids).
        sort_by(&:name).
        paginate(page: page, per_page: per_page)

      # pre-load configurable settings for the orgs, since the views will need to check if
      # notifications are restricted
      Configurable.preload_configuration(organizations)

      organizations
    end

    def org_routing_per_page
      ORG_NOTIFICATION_ROUTING_PER_PAGE
    end
  end
end
