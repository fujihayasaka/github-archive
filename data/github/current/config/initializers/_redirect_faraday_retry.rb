# typed: true
# frozen_string_literal: true

# This file's name is prefixed with an underscore to make sure rails loads
# this initializer before any others, ensuring that any instantiations of
# Faraday clients have the behavior we want.

Faraday::Request.register_middleware(retry: GitHub::FaradayMiddleware::Retries) unless Rails.env.test? #rubocop:disable GitHub/DoNotBranchOnRailsEnv
