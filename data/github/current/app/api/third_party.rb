# typed: true
# frozen_string_literal: true

# API endpoints for third-party apps.
class Api::ThirdParty < Api::App
  REQUEST_METHOD = "REQUEST_METHOD".freeze
  PATH_INFO = "PATH_INFO".freeze

  def deliver(*args)
    ActiveRecord::Base.connected_to(role: :reading) { super }
  end
end
