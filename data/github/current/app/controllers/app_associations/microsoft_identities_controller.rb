# typed: true
# frozen_string_literal: true

class AppAssociations::MicrosoftIdentitiesController < AppAssociations::BaseController
  # This needs to be specified because ApplicationController, which
  # `AppAssociations::BaseController` inherits from, does some feature flag
  # checks and those checks hit the Mysql1 cluster.
  depends_on_clusters ApplicationRecord::Mysql1

  # This path is used to verify the github.com domain as
  # the publisher domain of the following applications:
  #   GitHub Team Sync Azure application
  #   GitHub Subscription Permission Validation
  def index
    # Setting content-type header directly, as content-type: application/json; charset=utf-8 would confuse Azure
    response.headers["Content-Type"] = "application/json"
    render json: <<~JSON
    {
      "associatedApplications": [
        {
          "applicationId": "c3629460-0f4b-4a5d-9da5-6be011f495f5"
        },
        {
          "applicationId": "a3c04df9-984f-464e-8f9e-0c4a7e0c500d"
        }
      ]
    }
    JSON
  end
end
