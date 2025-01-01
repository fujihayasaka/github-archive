# typed: true
# frozen_string_literal: true

module ApplicationController::ClientVersionDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  CLIENT_VERSION_HEADER = "X-GitHub-Client-Version"

  requires_ancestor { ApplicationController }

  private

  def verify_client_version
    return unless user_or_global_feature_enabled?(:client_version_header)

    client_version = request.headers[CLIENT_VERSION_HEADER]

    return if client_version.blank?
    current_client_version = GitHubUI::Manifest.new.git_sha
    request_type = turbo_type || react_navigation_type || "fetch"

    GitHub.dogstats.increment("browser.client.version", tags: ["mismatch:#{client_version != current_client_version}", "request_type:#{request_type}", "logged_in:#{current_user.present?}"])
  end

  def report_ui_target
    return unless user_or_global_feature_enabled?(:report_ui_target)

    target = GitHubUI::Manifest.new.ui_manifest_target
    client_id = GitHub.context[:client_id]

    GitHub.dogstats.increment("ui.gh.manifest.target", tags: ["target:#{target}", "logged_in:#{current_user.present?}", "client_id:#{client_id.present?}"])
  end
end
