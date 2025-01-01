# typed: true
# frozen_string_literal: true

module GitHub
  module Exceptions
    class CauseCatalogServiceFinder
      RAILS_ROOT_FILTER_REGEX = /^#{ENV["RAILS_ROOT"]}\//
      PATH_REGEX = /(?<path>.*):\d+:.*/
      IGNORED_PATHS = Regexp.union([
        %r{lib/github/middleware/cluster_disabler.rb},
        %r{lib/github/connection_adapter_disabler.rb},
        %r{app/platform/loaders/active_record_association.rb},
        %r{lib/github/sorbet/runtime.rb},
        %r{config/ernicorn.rb}, # Support GitRPC::* exceptions
        %r{---- THE WIRE ----}, # Support GitRPC::* exceptions
        %r{bin/ernicorn$},
        %r{lib/github/cache/utils.rb},
        %r{config/instrumentation/redis.rb},
        %r{lib/github/redis/mutex.rb},
        %r{lib/github/cache/codec.rb},
        %r{lib/github/ds_extensions.rb},
        %r{lib/github/faraday_adapter/persistent_excon.rb},
        %r{lib/github/faraday_middleware/},
        %r{config/initializers/_redirect_faraday_retry.rb},
        %r{lib/launch/twirp/base_client.rb},
        %r{lib/redis_rate_limiter/redis_rate_limiter.rb},
        %r{app/controllers/application_controller/database_dependency.rb},
        %r{app/helpers/twirp_helper.rb},
        %r{app/helpers/resilience_helper.rb},
        %r{config/application.rb},
        %r{config/subscribers/trilogy/transaction_subscriber.rb},
        %r{config/subscribers/trilogy/query_warning_subscriber.rb},
        %r{lib/application_record/base.rb},
        %r{lib/database_selector.rb},
        %r{lib/github/active_record_enumerable_protection.rb},
        %r{lib/github/active_record_readonly_mode.rb},
        %r{lib/github/association_instrumenter.rb},
        %r{lib/github/batched_scope.rb},
        %r{lib/github/config/kv_dual_write.rb},
        %r{lib/github/config/mysql.rb},
        %r{lib/github/encoding.rb},
        %r{config/initializers/escape_utils.rb},
        %r{lib/github/prefill_associations.rb},
        %r{lib/github/request_duration_manager.rb},
        %r{lib/resilient/trilogy.rb},
        %r{lib/workflow.rb},
        %r{lib/github/request_duration_manager.rb},
        %r{lib/github/throttler.rb},
        %r{lib/github/domain_isolation},
        %r{lib/github/failbot_key_configuration.rb},
        %r{lib/github/resilience_mixin.rb},
        %r{packages/substrate/app/models/configuration.rb},
        %r{lib/gh/errors/decorator.rb},
        %r{lib/github/rate_limitable.rb},
        %r{lib/github/rate_limited_creation.rb},
        %r{lib/github/cache/zip.rb},
        %r{lib/configurable.rb},
        %r{lib/github/config.rb},
        %r{lib/github/config/context.rb},
        %r{lib/github/large_query_subscriber.rb},
        %r{app/helpers/pagination_helper.rb},
        %r{lib/github/failbot_key_filter.rb},
        %r{packages/substrate/app/models/coders/gzip.rb},
        %r{lib/github/cache/local.rb},
        %r{app/platform/loaders/configuration.rb},
        %r{app/helpers/url_helper.rb},
        %r{lib/gh/.*},
        %r{config/instrumentation/gitrpc.rb},
      ])
      APPLICATION_CODE_ROOT_REGEX = /\A(?:\.\/)?(?:app|config|lib|test|packages|\(\w*\))/

      def self.backtrace_cleaner
        @_cleaner ||= ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
          cleaner.remove_silencers!
          cleaner.add_filter { |line| line.gsub(RAILS_ROOT_FILTER_REGEX, "") }
          cleaner.add_silencer { |line| !APPLICATION_CODE_ROOT_REGEX.match?(line) }
          cleaner.add_silencer { |line| line.match?(IGNORED_PATHS) }
        end
      end

      def initialize(error, context: nil)
        @error = error
        @context = context || Failbot.context
      end

      def service_owner
        return nil if GitHub.serviceowners.nil?
        return nil unless @error.respond_to?(:backtrace)
        return nil if relevant_backtrace_line.blank?

        if matches = relevant_backtrace_line.match(PATH_REGEX)
          catalog_service_for_path(matches[:path])
        end
      rescue
        nil
      end

      def relevant_backtrace_line
        @_relevant_backtrace_line ||=
          self.class.backtrace_cleaner.clean(@error.backtrace).first ||
          self.class.backtrace_cleaner.clean(@error.backtrace, :noise).first # fallback to first line of backtrace
      end

      private

      def catalog_service_for_path(path)
        owner = GitHub.serviceowners.service_for_path(path, prefix: true)

        if relevant_backtrace_line.start_with?("app/platform") && owner == "github/graphql_api"
          Failbot.squash_contexts(@context)["catalog_service"]
        else
          owner
        end
      end
    end
  end
end
