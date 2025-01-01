# typed: false
# frozen_string_literal: true

module IntegrationsDirectoryHelper
  def stafftools_app_listing_path(listing)
    integration = listing.integration

    if integration.is_a?(OauthApplication)
      stafftools_user_application_path(integration.owner, integration.id,
        anchor: "integration-group")
    else
      stafftools_user_app_path(integration.owner, integration.slug,
        anchor: "integration-group")
    end
  end
end
