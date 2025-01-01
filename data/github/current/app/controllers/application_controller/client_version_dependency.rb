# typed: true
# frozen_string_literal: true

module ApplicationController::ClientVersionDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  CLIENT_VERSION_HEADER = "X-GitHub-Client-Version"

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    before_action :verify_client_version
  end

  private

  def verify_client_version
    return unless user_or_global_feature_enabled?(:client_version_header)

    client_version = request.headers[CLIENT_VERSION_HEADER]

    return if client_version.blank?
    current_client_version = GitHubUI::Manifest.new.git_sha
    request_type = turbo_type || react_navigation_type || "fetch"

    GitHub.dogstats.increment("browser.client.version", tags: ["mismatch:#{client_version != current_client_version}", "request_type:#{request_type}"])
  end
end
