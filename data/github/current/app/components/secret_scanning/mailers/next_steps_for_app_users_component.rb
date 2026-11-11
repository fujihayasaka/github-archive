# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class NextStepsForAppUsersComponent < ApplicationComponent
      SecretScanning::Mailers::NextStepsForAppUsersComponent

      sig do
        params(
          app_name: String,
          remediation_review_url: String,
          docs_url: String,
          docs_url_text: String,
          view_authorized_apps_url: String,
          view_authorized_apps_text: String
        ).void
      end
      def initialize(app_name:, remediation_review_url:, docs_url:, docs_url_text:, view_authorized_apps_url:, view_authorized_apps_text:)
        @app_name = app_name
        @remediation_review_url = remediation_review_url
        @docs_url = docs_url
        @docs_url_text = docs_url_text
        @view_authorized_apps_url = view_authorized_apps_url
        @view_authorized_apps_text = view_authorized_apps_text
      end
    end
  end
end
