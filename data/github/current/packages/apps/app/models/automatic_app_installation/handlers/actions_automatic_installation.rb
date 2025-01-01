# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class ActionsAutomaticInstallation < BaseHandler

      def install_integration
        # Actions app installation is handled in Repository::ActionsAppDependency#enable_actions_app
        nil
      end
    end
  end
end
