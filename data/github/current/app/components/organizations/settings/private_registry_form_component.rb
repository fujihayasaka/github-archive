# typed: true
# frozen_string_literal: true

module Organizations
  module Settings
    class PrivateRegistryFormComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      attr_reader :view, :form_action, :secret, :configuration, :public_key, :visibilities, :default_visibility, :total_count

      def initialize(view:, form_action:, public_key:, visibilities:, default_visibility:, total_count:, secret: nil, configuration: nil)
        @view = view
        @form_action = form_action
        @public_key = public_key
        @visibilities = visibilities
        @default_visibility = default_visibility
        @total_count = total_count
        @secret = secret
        @configuration = configuration
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
    end
  end
end
