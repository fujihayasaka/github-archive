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
      sha = ui_sha_override

      if sha.blank? || !GitHubUI::PreviewManifestStore.allowed?(git_sha: sha) && !Rails.env.development?
        GitHubUI::UIShaCookie.delete!(cookies)
        return
      end

      GitHub.context.push(ui_sha_override: sha)

      set_ui_sha_cookie(sha)
    end

    sig { returns(T.nilable(String)) }
    def ui_sha_override
      return if GitHub.enterprise?
      return if params[:_clear_ui_sha].present?
      return unless current_user&.employee? || Rails.env.development?

      # Use the query param first
      return params[:_ui_sha] if params[:_ui_sha].present?

      # Check the cookie if no param is set
      cookie = GitHubUI::UIShaCookie.read(cookies)
      cookie&.sha
    end

    sig { returns(T::Boolean) }
    def ui_sha_override_active?
      GitHub.context[:ui_sha_override].present?
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
