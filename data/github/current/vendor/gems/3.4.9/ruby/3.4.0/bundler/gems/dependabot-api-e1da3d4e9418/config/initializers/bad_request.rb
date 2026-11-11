# frozen_string_literal: true

require "./lib/middleware/bad_request"

# Install middleware to silence bad requests on internet-facing deployments
if Prius.get(:badge_service) || Prius.get(:actions_deployment)
  Rails.application.config.middleware.insert_after Failbot::Rails::Middleware,
                                                   Middleware::BadRequest
end
