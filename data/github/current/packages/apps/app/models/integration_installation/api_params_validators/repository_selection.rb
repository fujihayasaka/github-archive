# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  module ApiParamsValidators
    class RepositorySelection

      def self.validate!(repositories, params:)
        new(repositories, params).validate!
      end

      def initialize(repositories, params)
        @repositories = repositories
        @params = params
      end

      def validate!
        validate_repositories! if params["repository_selection"] == "selected"
      end

      private

      attr_reader :repositories, :params

      def validate_repositories!
        error_messages = {
          missing_repositories_key: "When 'repository_selection' is 'selected', the 'repositories' parameter must be provided as a non-empty array.",
          empty_repositories: "When 'repository_selection' is 'selected', 'repositories' cannot be empty.",
          invalid_repositories: "Repositories not found in this organization: %{repositories}. No change has been made to the installation."
        }

        ApiParamsValidators::Repositories.validate!(repositories, params:, error_messages: error_messages)
      end
    end
  end
end
