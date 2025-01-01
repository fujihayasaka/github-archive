# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module GitHub
  module Config
    module AuditLog
      extend T::Sig

      sig { returns(T.untyped) }
      def audit
        if GitHub.audit_log_production_env?
          @audit ||= T.let(
            begin
              multi_logger =
                if GitHub.enterprise?
                  loggers = []

                  syslog = ::Audit::Syslog::Logger.new
                  loggers.push(syslog)

                  if GitHub.audit_log_es_logger_enabled?
                    if !GitHub.es_clusters.empty?
                      GitHub.es_clusters.keys.each do |cluster_name|
                        loggers.unshift(::Audit::Elastic::Logger.new(cluster: cluster_name))
                      end
                    else
                      loggers.unshift(::Audit::Elastic::Logger.new)
                    end
                  end

                  Rails.logger.info("Configured audit loggers: #{loggers.map { |l| l.class.name }}")
                  ::Audit::Multi::Logger.new(*loggers)
                else
                  elastic = ::Audit::Elastic::Logger.new(cluster: GitHub.es_audit_log_cluster)
                  # only elastic will be enabled for dotcom
                  ::Audit::Multi::Logger.new(elastic)
                end
              searcher = ::Audit::Elastic::Searcher.new

              service = ::Audit::Service.new(logger: multi_logger, searcher: searcher)
              service.statsd = GitHub.stats
              service.on_error do |exc|
                Failbot.report(exc, fatal: "NO")
              end

              ::Audit::BackgroundJob.new(service)
            end,
          T.untyped)
        elsif GitHub.audit_log_dev_env? || GitHub.audit_log_staging_env?
          @audit ||= T.let(
            begin
              elastic = ::Audit::Elastic::Logger.new
              searcher = ::Audit::Elastic::Searcher.new
              service = ::Audit::Service.new logger: elastic, searcher: searcher
              service.statsd = GitHub.stats
              service.on_error do |exc|
                Failbot.report(exc, fatal: "NO")
              end

              T.let(::Audit::BackgroundJob.new(service), T.nilable(::Audit::BackgroundJob))
            end,
          T.untyped)
        elsif GitHub.audit_log_test_env?
          @audit ||= T.let(
            begin
              logger = ::Audit::Test::Logger.new
              searcher = ::Audit::Test::Searcher.new
              service = Audit::Test::Service.new(logger: logger, searcher: searcher)

              service.on_error do |exc|
                Kernel.puts "Audit Logging Error: #{exc}"
              end

              service
            end,
          T.untyped)
        else
          @audit ||= T.let(
            begin
              elastic = ::Audit::Elastic::Logger.new
              logger = ::Audit::Multi::Logger.new(elastic)
              searcher = ::Audit::Elastic::Searcher.new
              service = ::Audit::Service.new logger: logger, searcher: searcher

              service.on_error do |exc|
                Kernel.puts "Audit Logging Error: #{exc}"
              end

              service
            end,
          T.untyped)
        end
      end


      sig { params(audit: T.untyped).void }
      attr_writer :audit

      sig { returns(T::Boolean) }
      def audit_log_raise_on_verify?
        Rails.env.development? || Rails.env.test?
      end

    end
  end

  extend Config::AuditLog
end
