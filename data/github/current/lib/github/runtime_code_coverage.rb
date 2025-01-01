# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/ThreadUse

require "json"
require "coverage"

module GitHub
  # Implement runtime code coverage based on ruby's `Coverage` API.
  #
  # The entry point is `GitHub::RuntimeCodeCoverage.start`. Methods defined in
  # files that are `require`d after it's called have it's calls counted by
  # Ruby's `Coverage` module. It spawns a thread that periodically flushes the
  # coverage data to our data warehouse via Hydro. It's loaded at boot by
  # `config/application.rb`.
  #
  # Performance and memory are immediately affected by loading at boot even if
  # capturing is disabled during web requests. Flushing to Hydro takes time and
  # has significant performance impact.
  #
  # Hydro is done through the `GitHub.runtime_code_coverage_hydro_publisher`
  # since the data set is big (>86k events and >20mb) and might flood the usual
  # `GitHub.hydro_publisher`.
  class RuntimeCodeCoverage
    def self.enabled?
      # Shamelessly copied from <https://github.com/github/github/pull/309052>
      #
      # Similar but slightly different to "prefix environment". This allows
      # enabling RuntimeCodeCoverage for a percentage of dotcom processes and
      # configuring that by role, site, kube cluster and LUC environment.
      #
      # Examples:
      #   GH_RUNTIME_CODE_COVERAGE_ENABLE_PCT=100 (fully enabled)
      #   GH_RUNTIME_CODE_COVERAGE_ENABLE_PCT=50 (50% enabled)
      #   GH_RUNTIME_CODE_COVERAGE_ENABLE_PCT_FE_ASH1_IAD=50 (50% on dotcom1-ash1-iad)
      #   GH_RUNTIME_CODE_COVERAGE_ENABLE_PCT_FE_DOTCOM_1_ASH1_IAD=50 (50% on dotcom1-ash1-iad)
      #   GH_RUNTIME_CODE_COVERAGE_ENABLE_PCT_LUC_PERFORMANCE=100 (100% on LUC environment)

      env_keys = ["GH_RUNTIME_CODE_COVERAGE_ENABLE_PCT"]
      env_keys += env_keys.map { |x| "#{x}_#{GitHub.role}" }
      env_keys += env_keys.map { |x| "#{x}_#{GitHub.site}" }
      env_keys += env_keys.map { |x| "#{x}_#{GitHub.kubernetes_cluster_name}" } if GitHub.kubernetes_cluster_name
      env_keys += env_keys.map { |x| "#{x}_LUC_PERFORMANCE" } if ENV["LUC_PERFORMANCE"] == "1"

      env_keys.map! { |x| x.upcase.tr("-", "_") }

      enabled_pct = T.let(nil, T.nilable(String))
      # The variables in `env_keys` are sorted from least to most specific, so
      # try to get a value for `enable_pct` in reverse order to give the most
      # specific variables greater priority and fall back to zero if none is
      # defined.
      env_keys.reverse_each do |key|
        enabled_pct ||= ENV[key]
      end
      enabled_pct ||= "0"

      rand < (enabled_pct.to_f / 100.0)
    end

    def self.result(clear: true, stop: false)
      flush_time = Time.current
      result = Coverage.result(clear: clear, stop: stop)

      out = []
      result.each do |path, stats|
        stats[:methods].each do |key, count|
          klass = key[0]
          method = key[1]
          out << {
            flush_time: flush_time,
            path: path,
            class: klass.to_s,
            method: method.to_s,
            count: count
          }
        end
      end

      out
    end

    def self.flush
      t0 = Time.now
      flush_ok = 0
      flush_bad = 0

      # shuffle so that if there's some systematic error in delivery after some
      # number of events, then we don't always lose the same ones
      queue = result.shuffle

      begin
        GitHub.dogstats.gauge("gh.runtime_code_coverage.flush.size", queue.size)
        while event = queue.shift
          response = GitHub.runtime_code_coverage_hydro_publisher.publish(event, schema: "github.runtime_code_coverage.v0.MethodCallCount")

          if response.success?
            flush_ok += 1
          else
            flush_bad += 1
          end
        end
      ensure
        GitHub.dogstats.count("gh.runtime_code_coverage.flush.ok", flush_ok)
        GitHub.dogstats.count("gh.runtime_code_coverage.flush.bad", flush_bad)
        GitHub.dogstats.gauge("gh.runtime_code_coverage.flush.size", queue.size)
        t1 = T.must(Time.now)
        GitHub.dogstats.timing("gh.runtime_code_coverage.flush.time", (t1 - t0).to_f)
      end
    end

    def self.start(flush_interval: nil, flush_random: nil)
      @flush_interval = flush_interval || Integer(ENV.fetch("GH_RUNTIME_CODE_COVERAGE_FLUSH_INTERVAL", (60 * 60)))
      @flush_random   = flush_random || Integer(ENV.fetch("GH_RUNTIME_CODE_COVERAGE_FLUSH_RANDOM", @flush_interval / 10))

      Coverage.start(methods: true)

      @sender_thread ||= Thread.new do
        # wait for the constant to be loaded. this is done so that we can load
        # this file before Hydro is fully loaded and and get coverage for its
        # bits too!
        sleep 1 while !Object.const_defined?("Hydro::Schemas::Github::RuntimeCodeCoverage")

        loop do
          sleep(@flush_interval + rand * @flush_random)
          flush
        end
      end
    end

    def self.resume
      Coverage.resume  if Coverage.state == :suspended
    end

    def self.suspend
      Coverage.suspend if Coverage.state == :running
    end

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        if GitHub.flipper[:runtime_code_coverage_request].enabled?
          RuntimeCodeCoverage.resume
        else
          RuntimeCodeCoverage.suspend
        end
        @app.call(env)
      end
    end

    # This doesn't work but an alternative could be useful?
    #
    #module RailsEagerLoad
    #  def eager_load!
    #    RuntimeCodeCoverage.start
    #    super
    #  end
    #end
    #Rails::Engine.prepend(RailsEagerLoad)

    start if enabled?
  end
end
