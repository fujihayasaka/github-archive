# rubocop:disable GitHub/FeatureManagement/NoFlipperFeatureUsage
# typed: true
# frozen_string_literal: true

require "flipper"
require "flipper/adapters"
require "failbot"
require "failbot/middleware"

module Flipper
  module Adapters
    class InMemory
      include ::Flipper::Adapter

      RELOAD_INTERVAL = 10
      STALE_THRESHOLD = RELOAD_INTERVAL * 3
      KEY = "flipper.adapters.in_memory.%s"

      class_attribute :reload_task
      class_attribute :rollout_last_updated_at
      class_attribute :all_features, default: {}
      class_attribute :after_fork, default: false
      class_attribute :task_output

      class TimerTaskOutput
        attr_reader :id, :pid, :time, :error

        def initialize(id, pid, error)
          @id = id
          @pid = pid
          @time = Time.now.utc
          @error = error
        end

        def stale?
          time < Time.now.utc - Flipper::Adapters::InMemory::STALE_THRESHOLD
        end

        def inspect
          JSON.pretty_generate({
            id: id,
            pid: pid,
            same_pid: $$ == pid,
            time: time,
            stale: stale?,
            error: error,
          })
        end
      end

      class << self
        def mutex
          @mutex ||= Mutex.new
        end

        def reset_features
          mutex.synchronize do
            self.reload_task.try(:kill)
            self.reload_task = nil
            self.rollout_last_updated_at = nil
            self.all_features = {}
          end
        end

        def supported_prod_environment?
          Rails.env.production? && !GitHub.enterprise? && GitHub.role != :gitauth
        end

        def should_have_task?
          return false unless self.reload_task.nil?
          self.supported_prod_environment? || !Rails.env.production?
        end

        def after_fork?
          self.after_fork || !Rails.env.production?
        end

        def looped_reload_all_features(
          persistence_adapter: ::Flipper::Config.mysql_adapter,
          big_features: ::Flipper::Config.big_features,
          testing: false
        )
          is_console = GitHub.environment["GITHUB_PRODUCTION_CONSOLE"].present?
          GitHub.logger.info("Instantiating looped feature reload") unless is_console

          self.reload_task ||= with_thread(testing: testing, is_console: is_console) do |execution_id|
            Rails.logger.silence do
              reload_all_features(persistence_adapter: persistence_adapter, big_features: big_features, execution_id: execution_id)
            end

            GitHub.logger.info("[InMemory Reload Loop] Execution successfully completed", { "gh.feature_management.execution_id" => execution_id }) unless is_console
          end
        end

        def reload_all_features(persistence_adapter: ::Flipper::Config.mysql_adapter, big_features:, execution_id: nil)
          ActiveRecord::Base.connected_to(role: :reading) do
            if self.rollout_last_updated_at.nil?
              all_features = GitHub.dogstats.distribution_time("flipper.adapter.in_memory.reload_timing", tags: ["path:all"]) { persistence_adapter.get_all }
              rollout_last_updated_at = FlipperFeature.where.not(name: big_features).maximum(:rollout_updated_at)

              mutex.synchronize do
                self.all_features = all_features
                self.rollout_last_updated_at = rollout_last_updated_at
              end

              GitHub.dogstats.increment("flipper.adapter.in_memory.full_reload")
            else
              GitHub.dogstats.distribution_time("flipper.adapter.in_memory.reload_timing", tags: ["path:partial"]) do
                flags_to_refresh = FlipperFeature.updated_since(self.rollout_last_updated_at).without_big_features(big_features).pluck(:name, :rollout_updated_at)
                if flags_to_refresh.length == 0
                  GitHub.dogstats.increment("flipper.adapter.in_memory.no_reload")
                  GitHub.logger.info("Didn't reload features", {
                    "gh.feature_management.all_features_id" => Flipper::Adapters::InMemory.all_features&.object_id,
                    "gh.feature_management.reload_task_id" => Flipper::Adapters::InMemory.reload_task&.object_id,
                    "gh.feature_management.execution_id" => execution_id || "none",
                    "gh.feature_management.rollout_last_updated_at" => self.rollout_last_updated_at
                  }) unless GitHub.environment["GITHUB_PRODUCTION_CONSOLE"].present?
                  return
                end

                rollout_last_updated_at = T.let(flags_to_refresh.map { |(_, last_updated_at)| last_updated_at }.max, T.untyped)
                flipper_flags = flags_to_refresh.map { |(flag_name, _)| GitHub.flipper.feature(flag_name) }
                reloaded_flags = persistence_adapter.get_multi(flipper_flags)

                GitHub.dogstats.increment("flipper.adapter.in_memory.partial_reload")
                GitHub.dogstats.gauge("flipper.adapter.in_memory.partial_reload_count", reloaded_flags.size)

                mutex.synchronize do
                  self.rollout_last_updated_at = rollout_last_updated_at
                  reloaded_flags.each do |flag_name, flag|
                    self.all_features[flag_name] = flag
                  end
                end
              end
            end

            actor_and_group_size = self.all_features.values.flat_map { |f| [f[:actors].size, f[:groups].size] }.inject(:+) || 0
            GitHub.dogstats.gauge("flipper.adapter.in_memory.flags.count", self.all_features.size)
            GitHub.dogstats.gauge("flipper.adapter.in_memory.actor_groups.count", actor_and_group_size)

            GitHub.logger.info("Reloaded features", {
              "gh.feature_management.all_features_id" => Flipper::Adapters::InMemory.all_features&.object_id,
              "gh.feature_management.reload_task_id" => Flipper::Adapters::InMemory.reload_task&.object_id,
              "gh.feature_management.execution_id" => execution_id || "none",
              "gh.feature_management.rollout_last_updated_at" => self.rollout_last_updated_at
            }) unless GitHub.environment["GITHUB_PRODUCTION_CONSOLE"].present?
          end
        end

        private

        def with_thread(testing: false, is_console: false, &block)
          if !testing && Rails.env.test?
            # Allows us to mock the timer task in tests and not deal with threading
            block.call
            self.task_output = TimerTaskOutput.new("none", $$, nil)
          else
            execution_id = ""
            Thread.new do # rubocop:disable GitHub/ThreadUse
              loop do
                execution_id = SecureRandom.uuid
                output = nil

                begin
                  block.call(execution_id)

                  ActiveRecord::Base.connection_handler.clear_active_connections!(:reading)
                  output = TimerTaskOutput.new(execution_id, $$, nil)
                rescue Exception => err # rubocop:todo Lint/GenericRescue
                  Failbot.report(err)
                  GitHub.logger.error("[InMemory Reload Loop] Execution failed", { "exception" => err, "gh.feature_management.execution_id" => execution_id }) unless is_console
                  output = TimerTaskOutput.new(execution_id, $$, err)
                end

                mutex.synchronize { self.task_output = output }
                GitHub::DataCollector.reset_all
                sleep RELOAD_INTERVAL
              end
            end
          end
        rescue ThreadError => err
          GitHub.dogstats.increment("flipper.adapter.in_memory.thread_error")
          Failbot.report(err)
          GitHub.logger.error("[InMemory Reload Loop] Thread failed to start", { "exception" => err, "gh.feature_management.execution_id" => execution_id }) unless is_console
        end

      end

      attr_reader :name, :big_features

      # Public
      def initialize(persistence_adapter, big_features: [])
        @name = :memoized
        @big_features = big_features
        @persistence_adapter = persistence_adapter

        if self.class.all_features.nil?
          GitHub.logger.info("[InMemory] Uninitialized data detected") unless GitHub.environment["GITHUB_PRODUCTION_CONSOLE"].present?
          GitHub.dogstats.increment("flipper.adapter.in_memory.uninitialized_data.count")
          self.class.reload_all_features(big_features: big_features)
        end
      end

      def adapter_enabled?
        self.class.adapter_enabled?
      end

      def self.adapter_enabled?
        key = KEY % self.get_environment
        ActiveRecord::Base.connected_to(role: :reading) do
          FeatureManagement::Kv.store.get(key).value { "false" } == "true"
        end
      rescue GitHub::KV::UnavailableError
        false
      end

      # This function is originally from #lib/github/optimizely/config.rb. The file has since been removed
      # due to our contract with Optimizely ending and cleaning up of the Optimizely code. To ensure this code still works,
      # moved the function here were it's being called.
      def self.get_environment
        # staging and review lab is "production" when asking Rails.env
        # but we need staging and review lab to point at non production keys
        if GitHub.staging_lab?
          "development"
        elsif GitHub.dynamic_lab?
          "review_lab"
        else
          Rails.env
        end
      end

      def enable_adapter!
        self.class.enable_adapter!
      end

      def self.enable_adapter!
        key = KEY % self.get_environment
        ActiveRecord::Base.connected_to(role: :writing) { FeatureManagement::Kv.store.set(key, "true") }
      end

      def disable_adapter!
        self.class.disable_adapter!
      end

      def self.disable_adapter!
        key = KEY % self.get_environment
        ActiveRecord::Base.connected_to(role: :writing) { FeatureManagement::Kv.store.del(key) }
      end

      # Non-mutating calls, such as checks and gets, go to the global hash stored in memory.
      # This hash is updated periodically, but may be stale for short periods of time.
      # For this reason, mutations can take up to 30s to apply.

      # Public
      def features
        record_stale_data
        self.class.mutex.synchronize do
          Set.new(self.class.all_features.keys + @big_features)
        end
      end

      # Public
      def get(feature)
        # Defensive pattern alert! This line will kick off a background thread if we happen to have a dead thread
        # or we forgot to kick it off in the fork. This could happen, for example, in a console session or transition.
        if self.class.should_have_task?
          GitHub.logger.info("[InMemory] Loop started from within get", {
            "feature_flag.key" => feature.name.to_s,
            "gh.feature_management.after_fork" => self.class.after_fork,
          }) unless GitHub.environment["GITHUB_PRODUCTION_CONSOLE"].present?
          GitHub.dogstats.increment("flipper.adapter.in_memory.no_reload_task.count", tags: ["after_fork:#{self.class.after_fork}"])

          self.class.looped_reload_all_features(big_features: @big_features) if self.class.after_fork?
          return @persistence_adapter.get(feature)
        end

        if is_big_feature?(feature.name)
          return @persistence_adapter.get(feature)
        end

        feature_config = fetch_key(feature.name.to_s)
        if feature_config.nil?
          GitHub.logger.info("[InMemory] Feature not found, using fallback", {
            "feature_flag.key" => feature.name
          }) unless GitHub.environment["GITHUB_PRODUCTION_CONSOLE"].present?

          GitHub.dogstats.increment("flipper.adapter.in_memory.feature_not_found")
          return @persistence_adapter.get(feature)
        end

        feature_config
      end

      # Public
      def get_multi(features)
        features.map do |feature|
          [feature.name.to_s, get(feature)]
        end.to_h
      end

      # Public
      def get_all
        return @persistence_adapter.get_all if big_features.present?
        record_stale_data
        self.class.mutex.synchronize do
          self.class.all_features
        end
      end

      # Public. Look up a feature value for the given actor.
      def feature_enabled?(feature_key, actor_id)
        return @persistence_adapter.feature_enabled?(feature_key, actor_id) if is_big_feature?(feature_key)
        # Don't call actors_value as that returns an array when we want the Set
        # to make it an O(1) call.
        actors = fetch_key(feature_key.to_s)&.dig(:actors)
        return false if actors.nil?
        actors.include?(actor_id)
      end

      # Public.
      def actors_value(feature_key)
        return @persistence_adapter.actors_value(feature_key) if is_big_feature?(feature_key)
        fetch_key(feature_key.to_s)&.dig(:actors)&.to_a
      end

      # Mutating calls will call up to the underlying Adapter (usually MySQL) and force a reload on this unicorn.
      # Other unicorns will update their cache periodically and get the changes shortly.
      # These are ok to call into MySQL since they are only called by actions in dev tools, and other mutating actions.
      # All get/checks are done against an in-memory hash

      # Public
      def add(feature)
        result = @persistence_adapter.add(feature)
        reload if Rails.env.test?
        result
      end

      # Public
      def remove(feature)
        result = @persistence_adapter.remove(feature)
        reload if Rails.env.test?
        result
      end

      # Public
      def clear(feature)
        result = @persistence_adapter.clear(feature)
        reload if Rails.env.test?
        result
      end

      # Public
      def enable(feature, gate, thing)
        result = @persistence_adapter.enable(feature, gate, thing)
        reload if Rails.env.test?
        result
      end

      # Public
      def disable(feature, gate, thing)
        result = @persistence_adapter.disable(feature, gate, thing)
        reload if Rails.env.test?
        result
      end

      private

      def is_big_feature?(feature)
        big_features.include?(feature.to_s)
      end

      def reload
        return unless Rails.env.test?
        self.class.rollout_last_updated_at = nil
        self.class.reload_all_features(
          persistence_adapter: @persistence_adapter,
          big_features: @big_features
        )
      end

      def record_stale_data
        return if self.task_output.nil?
        return unless self.task_output.stale?
        GitHub.dogstats.count("flipper.adapter.in_memory.stale_data.count", 1)
      end

      # Some adapters override the default keys to use special formats, such as memcached using `flipper_feature:KEY`
      # This doesn't seem to always apply if a key isnt cached in memcache for example, so to make sure we support the different cases
      # We will loop through possible keys and take the first result we find
      #
      def fetch_key(feature_key)
        record_stale_data
        feature_key = feature_key.to_s

        self.class.mutex.synchronize do
          self.class.all_features&.dig(feature_key)
        end
      end
    end
  end
end

# rubocop:enable GitHub/FeatureManagement/NoFlipperFeatureUsage
