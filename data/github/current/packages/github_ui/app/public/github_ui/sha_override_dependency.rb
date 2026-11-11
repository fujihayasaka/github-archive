# typed: strict
# frozen_string_literal: true

module GitHubUI
  module ShaOverrideDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))

      helper_method :ui_sha_override_active?, :github_ui_commit_url
    end

    sig { void }
    def set_ui_sha_override
      preview_sha = ui_sha_override

      if preview_sha.blank? || !GitHubUI::PreviewManifestStore.allowed?(git_sha: preview_sha)
        GitHubUI::UIShaCookie.delete!(cookies)
        preview_sha = nil
      end

      # Always set UI target to preview if a cookie/query override is present, even if header may override
      if preview_sha.present?
        GitHub.context.push(is_ui_preview: true)
        set_ui_sha_cookie(preview_sha)
      end

      # Override set in header takes precedence
      resolved_sha = ui_sha_from_header || preview_sha

      GitHub.context.push(ui_sha_override: resolved_sha) if resolved_sha.present?
    end

    sig { returns(T.nilable(String)) }
    def ui_sha_override
      # The checks below only apply to query param and cookie sources, not to header
      return if GitHub.enterprise?
      return if params[:_clear_ui_sha].present?
      return unless current_user&.employee? || Rails.env.development?

      # Use the query param first
      return params[:_ui_sha] if params[:_ui_sha].present?

      # Check the cookie if no param is set
      cookie = GitHubUI::UIShaCookie.read(cookies)
      cookie&.sha
    end

    sig { returns(T.nilable(String)) }
    def ui_sha_from_header
      header_value = request.headers["X-GitHub-UI-SHA"]
      return nil if header_value.blank?

      # Parse format: <sha>.<timestamp>.<signature>
      parts = header_value.split(".", 3)
      return nil if parts.length != 3

      sha, timestamp_str, signature = parts
      return nil if sha.blank? || timestamp_str.blank? || signature.blank?

      # Validate timestamp is within acceptable range (10 minutes)
      timestamp = timestamp_str.to_i
      return nil unless timestamp > 10.minutes.ago.to_i && timestamp < 10.minutes.from_now.to_i

      # Verify HMAC signature
      return nil unless verify_ui_sha_hmac(sha, timestamp_str, signature)

      sha
    end

    sig { params(sha: String, timestamp: String, signature: String).returns(T::Boolean) }
    def verify_ui_sha_hmac(sha, timestamp, signature)
      hmac_keys = GitHub.api_internal_ui_manifests_hmac_keys
      return false if hmac_keys.blank?

      # Check if any key produces a matching signature
      # The message is sha.timestamp
      message = "#{sha}.#{timestamp}"
      hmac_keys.any? do |key|
        expected_signature = OpenSSL::HMAC.hexdigest("sha256", key, message)
        ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
      end
    end

    sig { returns(T::Boolean) }
    def ui_sha_override_active?
      ui_sha_override.present?
    end

    sig { params(sha: String).void }
    def set_ui_sha_cookie(sha)
      cookie = GitHubUI::UIShaCookie.generate(user: current_user, sha: sha)

      return unless cookie.present?
      cookie.save!(cookies)
    end

    sig { returns(T.nilable(String)) }
    def github_ui_commit_url
      sha = ui_sha_override
      return unless sha.present?

      "https://github.com/github/github-ui/commit/#{sha}"
    end
  end
end
