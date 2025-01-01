# typed: strict
# frozen_string_literal: true

module GitHubUI
  module ShaOverrideDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    sig { void }
    def set_ui_sha_override
      sha = ui_sha_override
      GitHub.context.push(ui_sha_override: sha)

      return unless sha.present?

      # set cookie to persist the override across navigations
      response.set_cookie(:_ui_sha, value: sha, domain: ".#{GitHub.host_name}")
    end

    sig { returns(T.nilable(String)) }
    def ui_sha_override
      return unless GitHub.context[:staff_request] == "true" || Rails.env.development?

      params[:_ui_sha].presence || cookies[:_ui_sha].presence
    end
  end
end
