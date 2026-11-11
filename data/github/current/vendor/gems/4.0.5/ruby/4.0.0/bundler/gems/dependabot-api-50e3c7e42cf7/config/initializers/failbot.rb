# frozen_string_literal: true

require "failbot"
require "failbot/rails"
require "./lib/middleware/failbot"

# Replace the failbot_rails middleware and insert the new one at the same point
Rails.application.config.middleware.delete Failbot::Rails::Middleware
Rails.application.middleware.insert_after ActionDispatch::DebugExceptions,
                                          Middleware::Failbot,
                                          { app: "dependabot-api" }
Rails.application.config.to_prepare do
  ActiveSupport.on_load(:action_controller) do
    include Middleware::ActionControllerUtilities
  end
end
