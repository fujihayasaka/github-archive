# typed: true
# frozen_string_literal: true

ReActionView.configure do |config|
  config.intercept_erb = ENV["REACTIONVIEW_ENABLED"] == "1" || Rails.env.development? || Rails.env.test?
  config.validation_mode = :raise
  config.debug_mode = false
end

Rails.logger.info("ReActionView enabled: #{ReActionView.config.intercept_erb}")
