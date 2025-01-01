# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module OIDCProviders
      CONFIG_PATH = GitHub::AppEnvironment.root.join("config/oidc_providers.yml")

      # Public: Read the yml file that contains the configuration for different environments
      #  and return providers for the specific environment.  This method should only be accessed
      #  once during boot time.
      #
      #  Supported environments are: development, test, production, and review_lab
      #
      # Returns a Hash
      def oidc_providers_config
        YAML.safe_load(File.read(CONFIG_PATH))[oidc_environment].with_indifferent_access
      end

      # Public: A method to access the oidc providers.  It returns a hash of providers access by a key.
      #
      #  supported keys: :azure
      #
      # Returns a Hash
      def oidc_providers
        @oidc_providers ||= oidc_providers_config
      end
      attr_writer :oidc_providers

      # Public: A way to determine a correct environment and returns it.  Also adds ability to mock
      # the environment during testing.
      #
      # Returns string
      def oidc_environment
        if GitHub.dynamic_lab?
          "review_lab"
        else
          GitHub::AppEnvironment.env
        end
      end
    end
  end

  extend Config::OIDCProviders
end
