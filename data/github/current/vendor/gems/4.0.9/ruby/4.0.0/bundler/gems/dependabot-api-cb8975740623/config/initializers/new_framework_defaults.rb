# frozen_string_literal: true

# Allow non-SSL requests to the healthcheck endpoint (/_ping)
Rails.application.config.ssl_options = {
  redirect: {
    exclude: ->(request) { request.path.start_with?("/_ping") },
  },
}
