# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    module Registry
      # Registry enabled in GHES
      def registry_enabled_for_enterprise?
        return @registry_enabled_for_enterprise if defined?(@registry_enabled_for_enterprise)
        @registry_enabled_for_enterprise = ENV.fetch("ENTERPRISE_REGISTRY_ENABLED_FOR_ENTERPRISE", "false") == "true"
      end
      attr_writer :registry_enabled_for_enterprise

      # Registry V2 enabled in GHES
      def registry_v2_enabled_for_enterprise?
        return @registry_v2_enabled_for_enterprise if defined?(@registry_v2_enabled_for_enterprise)
        @registry_v2_enabled_for_enterprise = ENV.fetch("ENTERPRISE_PACKAGES_REGISTRY_V2_ENABLED", "false") == "true"
      end
      attr_writer :registry_v2_enabled_for_enterprise

      def package_registry_cdn_enabled?
        return @package_registry_cdn_enabled if defined?(@package_registry_cdn_enabled)
        @package_registry_cdn_enabled = FeatureFlag.vexi.enabled?(:package_registry_cdn, default: false)
      end
      attr_writer :package_registry_cdn_enabled

      def package_registry_enabled?
        return @package_registry_enabled if defined?(@package_registry_enabled)
        @package_registry_enabled = !single_tenant_enterprise?
      end
      attr_writer :package_registry_enabled

      # Both v1 and v2 packages are enabled
      def packages_enabled?
        GitHub.package_registry_enabled? || (GitHub.enterprise? && registry_enabled_for_enterprise? && registry_v2_enabled_for_enterprise?)
      end
      attr_writer :packages_enabled

      def docker_api_routes_reserved?
        @docker_api_routes_reserved if defined?(@docker_api_routes_reserved)
        @docker_api_routes_reserved = ENV.fetch("DOCKER_API_ROUTES_RESERVED", "false") == "true"
      end
      attr_writer :docker_api_routes_reserved

      def container_registry_mode
        return @container_registry_mode if defined?(@container_registry_mode)
        @container_registry_mode = ENV.fetch("ENTERPRISE_CONTAINER_REGISTRY_MODE", "enabled")
      end
      attr_writer :container_registry_mode

      # GitHub Package Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/packages/learn-github-packages/introduction-to-github-packages")
      def about_github_package_registry_url
        "#{help_url}/packages/learn-github-packages/introduction-to-github-packages"
      end

      # GitHub Package Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/github/managing-packages-with-github-packages/deleting-a-package")
      def github_package_registry_delete_policy_url
        "#{help_url}/github/managing-packages-with-github-packages/deleting-a-package"
      end

      # GitHub Docker Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/articles/configuring-docker-for-use-with-github-package-registry/")
      def docker_github_package_registry_url
        "#{help_url}/articles/configuring-docker-for-use-with-github-package-registry/"
      end

      # GitHub Containers Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/packages/working-with-a-github-packages-registry/working-with-the-container-registry")
      def container_github_package_registry_url
        "#{help_url}/packages/working-with-a-github-packages-registry/working-with-the-container-registry/"
      end

      # GitHub Maven Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/articles/configuring-apache-maven-for-use-with-github-package-registry/")
      def maven_github_package_registry_url
        "#{help_url}/articles/configuring-apache-maven-for-use-with-github-package-registry/"
      end

      # GitHub Gradle Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/articles/configuring-gradle-for-use-with-github-package-registry/")
      def gradle_github_package_registry_url
        "#{help_url}/articles/configuring-gradle-for-use-with-github-package-registry/"
      end

      # GitHub npm Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/articles/configuring-npm-for-use-with-github-package-registry/")
      def npm_github_package_registry_url
        "#{help_url}/articles/configuring-npm-for-use-with-github-package-registry/"
      end

      # GitHub RubyGems Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/articles/configuring-rubygems-for-use-with-github-package-registry/")
      def rubygems_github_package_registry_url
        "#{help_url}/articles/configuring-rubygems-for-use-with-github-package-registry/"
      end

      # GitHub NuGet Registry Documentation
      #
      # Returns the URL string ("https://docs.github.com/articles/configuring-nuget-for-use-with-github-package-registry/")
      def nuget_github_package_registry_url
        "#{help_url}/articles/configuring-nuget-for-use-with-github-package-registry/"
      end

      # Returns documentation URL string for a given package type symbol
      def github_package_registry_url(package_type)
        if [:docker, :maven, :npm, :rubygems, :nuget, :container].include?(package_type)
          send("#{package_type}_github_package_registry_url")
        else
          about_github_package_registry_url
        end
      end

      # The number of shards to use when creating the `registry_packages` index.
      def es_shard_count_for_registry_packages
        @es_shard_count_for_registry_packages ||= 1
      end
      attr_writer :es_shard_count_for_registry_packages

      def api_internal_package_registry_hmac_keys
        @api_internal_package_registry_hmac_keys ||=
          ENV["API_INTERNAL_PACKAGE_REGISTRY_HMAC_KEYS"].to_s.split
      end
      attr_writer :api_internal_package_registry_hmac_keys

      attr_accessor :maven_package_registry_azurite_development_storage_proxy_uri

      def maven_package_registry_azure_account_name
        @maven_package_registry_azure_account_name ||=
          ENV["AZURE_ACCOUNT_NAME_MAVEN_PACKAGE_REGISTRY"]
      end
      attr_writer :maven_package_registry_azure_account_name

      def maven_package_registry_azure_account_key
        @maven_package_registry_azure_account_key ||=
          ENV["AZURE_ACCOUNT_KEY_MAVEN_PACKAGE_REGISTRY"]
      end

      def maven_package_registry_azure_container_name
        @maven_package_registry_azure_container_name ||=
          ENV["AZURE_CONTAINER_NAME_MAVEN_PACKAGE_REGISTRY"]
      end
      attr_writer :maven_package_registry_azure_container_name
    end
  end

  extend Config::Registry
end
