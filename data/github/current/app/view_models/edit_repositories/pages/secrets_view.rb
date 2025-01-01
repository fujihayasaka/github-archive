# typed: false
# frozen_string_literal: true

module EditRepositories
  module Pages
    class SecretsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      # Page relies heavily on layout which makes it a poor candidate for a component at the moment
      attr_reader :app_name, :current_repository, :current_user
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

      def dependabot?
        app_name == Secrets::AppsHelper::DEPENDABOT_APP_NAME
      end

      def codespaces_dev_env_secrets?
        app_name == Secrets::AppsHelper::CODESPACES_APP_NAME && current_user.feature_enabled?(:codespaces_dev_env_secrets)
      end

      def blank_slate_title
        if app_name == Secrets::AppsHelper::ACTIONS_APP_NAME
          "No workflows have been added to this repository."
        else
          "You do not have access to #{app_display_name} secrets."
        end
      end

      def repository_secrets_blank_slate_description
        if view.dependabot?
          "Encrypted secrets allow you to store private access tokens so that Dependabot can update dependencies from private registries."
        else
          "Encrypted secrets allow you to store sensitive information, such as access tokens, in your repository."
        end
      end
    end
  end
end
