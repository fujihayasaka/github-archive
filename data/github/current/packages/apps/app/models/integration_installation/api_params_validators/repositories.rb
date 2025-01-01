# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  module ApiParamsValidators
    class Repositories
      include GitHub::Memoizer

      DEFAULT_ERROR_MESSAGES = {
        missing_repositories_key: "Missing required field: repositories",
        empty_repositories: "'repositories' cannot be empty. At least one repository must be included.",
        invalid_repositories: "Repositories not found in this organization: %{repositories}. No change has been made to the installation."
      }.freeze

      def self.validate!(repositories, params:, error_messages: {})
        new(repositories, params, error_messages).validate!
      end

      def initialize(repositories, params, error_messages = {})
        @repositories                     = repositories
        @params                           = params
        @repositories_for_installation    = Array(params["repositories"])
        @error_messages                   = DEFAULT_ERROR_MESSAGES.merge(error_messages)
      end

      def validate!
        ensure_repositories_key_present!
        ensure_repositories_not_empty!
        ensure_repositories_valid!
      end

      private

      attr_reader :repositories, :params, :repositories_for_installation, :error_messages

      def ensure_repositories_key_present!
        return if params.key?("repositories")

        raise_error(:missing_repositories_key)
      end

      def ensure_repositories_not_empty!
        return unless repositories_for_installation.empty?

        raise_error(:empty_repositories)
      end

      def ensure_repositories_valid!
        invalid_repositories = repositories_for_installation.difference(found_repository_names)
        return if invalid_repositories.empty?

        raise_error(:invalid_repositories, invalid_repositories.join(", "))
      end

      memoize def found_repository_names
        repositories.pluck(:name)
      end

      def raise_error(type, list = nil)
        message =
          if list
            format(error_messages[type], repositories: list)
          else
            error_messages[type]
          end

        raise Error.new(message, type)
      end
    end
  end
end
