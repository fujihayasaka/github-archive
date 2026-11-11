# typed: true
# frozen_string_literal: true

module Settings
  module Organization
    class SecretsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      # Page relies heavily on layout which makes it a poor candidate for a component at the moment
      attr_reader :app_name, :current_organization, :current_user

      def page_title
        Secrets::AppsHelper.page_title_for(app_name, current_user)
      end

      def app_display_name
        Secrets::AppsHelper.display_name_for(app_name)
      end

      def selected_link
        Secrets::AppsHelper.highlight_for(app_name, current_user)
      end

      def actions?
        app_name == Secrets::AppsHelper::ACTIONS_APP_NAME
      end

      def codespaces?
        app_name == Secrets::AppsHelper::CODESPACES_APP_NAME
      end

      def dependabot?
        app_name == Secrets::AppsHelper::DEPENDABOT_APP_NAME
      end

      def repository_items_data_url(secret_name: nil)
        urls.settings_org_secrets_repository_items_path(current_organization, page: 1, app_name: app_name, secret_name: secret_name)
      end

      def repository_items_aria_id_prefix(secret_name: nil)
        return app_name unless secret_name.present?
        "#{app_name}-#{secret_name}"
      end
    end
  end
end
