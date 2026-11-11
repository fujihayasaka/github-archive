# frozen_string_literal: true

require "middleware/secure_headers"

Rails.application.config.middleware.insert_before Rack::Cors,
                                                  Middleware::SecureHeaders
