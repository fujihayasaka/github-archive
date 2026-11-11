# typed: true
# frozen_string_literal: true

module Organizations
  module Settings
    class PrivateRegistryFormComponent < ApplicationComponent
      attr_reader :view, :form_action, :secret, :configuration, :public_key, :visibilities, :default_visibility, :total_count,
        :selected_repositories, :selected_repository_global_ids

      def initialize(view:, form_action:, public_key:, visibilities:, default_visibility:, total_count:, secret: nil, configuration: nil, selected_repositories: [], selected_repository_global_ids: Set.new)
        @view = view
        @form_action = form_action
        @public_key = public_key
        @visibilities = visibilities
        @default_visibility = default_visibility
        @total_count = total_count
        @secret = secret
        @configuration = configuration
        @selected_repositories = selected_repositories
        @selected_repository_global_ids = selected_repository_global_ids
      end

      def create_form?
        form_action == :create
      end

      def update_form?
        form_action == :update
      end

      def registry_url
        configuration&.url
      end

      def registry_type
        configuration&.registry_type
      end

      def registry_username
        configuration&.username
      end

      def updating_username_and_password?
        update_form? && registry_username.present?
      end

      def updating_oidc?
        update_form? && configuration&.oidc?
      end

      def replaces_base
        configuration&.replaces_base || false
      end

      def auth_type
        configuration&.auth_type
      end
    end
  end
end
