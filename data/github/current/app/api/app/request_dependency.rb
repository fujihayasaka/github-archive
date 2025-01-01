# typed: true
# frozen_string_literal: true

module Api::App::RequestDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  def request_id
    request.env[Rack::RequestId::GITHUB_REQUEST_ID] || ""
  end
end
