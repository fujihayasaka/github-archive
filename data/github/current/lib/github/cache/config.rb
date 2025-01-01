# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    class Config
      autoload :Comparator, "github/cache/config/comparator"
      autoload :Servers, "github/cache/config/servers"

      ENV_CONFIG_PATH = "#{GitHub::AppEnvironment.root}/config/memcached_partitioned.yml"
      SERVER_CONFIG_PATH = "#{GitHub::AppEnvironment.root}/config/memcached_servers.yml"

      class Environment < T::Enum
        enums do
          Default = new
          Dotcom = new
          Proxima = new
          Enterprise = new
        end
      end

      def initialize(overrides: nil)
        @overrides = overrides
      end

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String])).returns(T::Hash[Symbol, T.untyped]) }
      def for_partition(partition, sites: nil)
        config = partition_config(partition).merge({ servers: servers(partition:, sites:) })

        return config.merge(@overrides) if @overrides

        config
      end

      def partitions
        env_config.symbolize_keys.keys
      end

      private

      sig { returns(T::Hash[String, T.untyped]) }
      def env_config
        config = YAML.load(File.read(ENV_CONFIG_PATH), aliases: true)
        env = if environment == Environment::Proxima
          "proxima"
        else
          GitHub::AppEnvironment.env
        end

        config[env]
      end

      sig { params(partition: Symbol).returns(T::Hash[Symbol, T.untyped]) }
      def partition_config(partition)
        raise ArgumentError.new("No config found for partition: #{partition}") unless partitions.include?(partition)

        config = env_config[partition.to_s].symbolize_keys

        config[:codec] = GitHub::Cache::Codec
        config[:namespace] ||= "github-"
        config[:namespace] << if GitHub.employee_unicorn?
          GitHub.host_name[0..9]
        else
          GitHub::AppEnvironment.env
        end
        config
      end

      sig { params(partition: Symbol, sites: T.nilable(T::Array[String])).returns(T::Array[String]) }
      def servers(partition:, sites: nil)
        env = environment
        case env
        when Environment::Dotcom
          Servers::Dotcom.new.servers(partition:, sites:)
        when Environment::Proxima
          Servers::Proxima.new.servers
        when Environment::Enterprise
          Servers::Enterprise.new.servers
        when Environment::Default
          Servers::Default.new.servers
        else
          T.absurd(env)
        end
      end

      sig { returns(Environment) }
      def environment
        case
        when GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?
          Environment::Default
        when GitHub.multi_tenant_enterprise?
          Environment::Proxima
        when GitHub.single_tenant_enterprise?
          Environment::Enterprise
        when GitHub::AppEnvironment.production?
          Environment::Dotcom
        else
          Environment::Default
        end
      end
    end
  end
end
