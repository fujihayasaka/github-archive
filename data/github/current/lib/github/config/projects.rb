# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Projects
      # Allow for classic projects to be created in specific environments
      #
      # Currently we block creating classic projects in dotcom (unless the account already has existing
      # classic projects) and Proxima (because we don't want to support those there).
      #
      # GHES is the only target currently where we don't wish to restrict creating classic projects,
      # until we have a clear timeline to deprecating classic projects there.
      #
      #  Checks for ENTERPRISE_PROJECTS_CLASSIC_CREATION_ENABLED environment variable.
      def projects_classic_creation_enabled?
        if defined?(@projects_classic_creation_enabled) && !@projects_classic_creation_enabled.nil?
          return @projects_classic_creation_enabled
        end

        @projects_classic_creation_enabled = GitHub.enterprise?
      end
      attr_writer :projects_classic_creation_enabled
    end
  end

  extend Config::Projects
end
