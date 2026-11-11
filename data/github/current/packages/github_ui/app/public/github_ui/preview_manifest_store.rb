# typed: strict
# frozen_string_literal: true

module GitHubUI
  class PreviewManifestStore
    class MissingError < StandardError
    end

    sig { params(git_sha: String).returns(T::Boolean) }
    def self.allowed?(git_sha:)
      return true if Rails.env.development?

      # Reuse the connection from ManifestStore so that we can share configuration and keepalives
      connection = GitHubUI::ManifestStore.ui_deploys_preview_faraday_connection
      return false unless connection

      path = "/target/preview/#{git_sha}/allowed"
      response = connection.get(path)

      response.status == 200
    rescue StandardError => e
      GitHub.logger.error("Exception when checking preview SHA with ui-deploys: #{e.message}", {
        "exception.class": e.class.name,
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
      false
    end
  end
end
