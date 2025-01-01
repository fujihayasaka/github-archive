# typed: true
# frozen_string_literal: true

require "set"
require "scientist"
require_relative "../../feature_management/feature_flag_hub_forwarder"
require_relative "../../feature_management/feature_flag_hub_client_error"

module Flipper
  module Adapters
    class Mysql
      include Flipper::Adapter
      include Scientist

      class ConcurrencyError < StandardError; end
      class ActorGateLimitError < StandardError; end

      ACTOR_GATE_KEY = Flipper::Gates::Actor.new.key
      BOOLEAN_GATE_KEY = Flipper::Gates::Boolean.new.key
      PERCENTAGE_ACTORS_GATE_KEY = Flipper::Gates::PercentageOfActors.new.key
      PERCENTAGE_TIME_GATE_KEY = Flipper::Gates::PercentageOfTime.new.key
      GROUP_GATE_KEY = Flipper::Gates::Group.new.key
      NON_ACTOR_GATE_KEYS = [BOOLEAN_GATE_KEY, PERCENTAGE_ACTORS_GATE_KEY, PERCENTAGE_TIME_GATE_KEY, GROUP_GATE_KEY]

      attr_reader :name
      attr_reader :enable_forwarder
      attr_reader :forwarder_service

      def initialize(enable_forwarder, exclude_actors_for: [])
        @name = :mysql
        @exclude_actors_for = exclude_actors_for
        @enable_forwarder = enable_forwarder

        # Disable the forwarder in the timerd script environments
        if defined?(TIMERD_SCRIPT)
          @enable_forwarder = false
        end

        if @enable_forwarder == true
          begin
            @forwarder_service = FeatureManagement::FeatureFlagHubForwarder.new
          rescue NameError, Faraday::Error => e
            @enable_forwarder = false
            Failbot.report(e)
            GitHub.dogstats.increment("gh.feature_management.forwarder.mysql_initialization_failure.count", tags: ["failure_reason:name_error"])
          rescue FeatureManagement::FeatureFlagHubClientError => e
            @enable_forwarder = false
            Failbot.report(e)
            GitHub.dogstats.increment("gh.feature_management.forwarder.mysql_initialization_failure.count", tags: ["failure_reason:client_error"])
          end
        end
      end

      # Public: return the set of known features.
      def features
        ActiveRecord::Base.connected_to(role: :reading) do
          rows = ApplicationRecord::Domain::Features.connection.select_rows(<<-SQL)
            SELECT name FROM flipper_features
          SQL
          rows.flatten.to_set
        end
      end

      # Public: Adds a feature to the set of known features.
      #
      # Returns true
      def add(feature)
        feature_id(feature)
        true
      end

      # Public: Removes a feature from the set of known features and clears
      # all the values for the feature.
      #
      # Returns true
      def remove(feature)
        ::FlipperFeature.transaction do
          clear(feature)
          binds = {
            name: feature.key.to_s,
          }
          ApplicationRecord::Domain::Features.connection.delete(Arel.sql(<<-SQL, **binds))
            DELETE FROM flipper_features WHERE name = :name
          SQL
          @forwarder_service.delete_feature_flag(feature.key.to_s) if enable_forwarder
        end
        true
      end

      # Public: Clears all the gate values for a feature.
      #
      # Returns true
      def clear(feature)
        binds = {
          name: feature.key.to_s,
        }
        ApplicationRecord::Domain::Features.connection.delete(Arel.sql(<<-SQL, **binds))
          DELETE flipper_gates
          FROM flipper_gates
          INNER JOIN flipper_features ON flipper_features.id = flipper_gates.flipper_feature_id
          WHERE flipper_features.name = :name
        SQL
        @forwarder_service.clear_feature_flag_gates(feature.key.to_s) if enable_forwarder
        update_rollout_timestamp(feature)

        true
      end

      # Public: Gets the values for all gates for a given feature.
      #
      # feature - a Flipper::Feature
      #
      # Returns a Hash of Flipper::Gate#key => value.
      def get(feature)
        GitHub.dogstats.increment("flipper.adapter.mysql.count", tags: ["caller:get"])

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        tags = ["caller:get", "feature:#{feature.key}"]
        ActiveRecord::Base.connected_to(role: :reading) do
          binds = {
            name: feature.key.to_s,
          }
          db_gates = Arel.sql <<-SQL, **binds
            SELECT
              flipper_gates.name AS name,
              flipper_gates.value AS value
            FROM flipper_gates
            INNER JOIN flipper_features ON flipper_features.id = flipper_gates.flipper_feature_id
            WHERE flipper_features.name = :name
          SQL
          if exclude_actors?(feature)
            tags << "is_big_feature:true"
            db_gates += Arel.sql <<-SQL, actor: ACTOR_GATE_KEY
              AND flipper_gates.name <> :actor
            SQL
          end

          result = result_for_feature(feature, ApplicationRecord::Domain::Features.connection.select_rows(db_gates))
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          GitHub.dogstats.distribution("flipper.adapter.mysql.duration", duration, tags: tags)
          result
        end
      end

      # Public: Gets the values for all gates for provided features.
      #
      # features - an Array of Flipper::Feature's
      #
      # Returns a Hash of Hashes (gate key => gate value(s)).
      def get_multi(features)
        return {} if features.empty?

        GitHub.dogstats.increment("flipper.adapter.mysql.count", tags: ["caller:get_multi"])

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        tags = ["caller:get_multi"]
        ActiveRecord::Base.connected_to(role: :reading) do
          exclude_actors_for, include_actors_for = features.partition { |f| exclude_actors?(f) }

          queries = []

          unless include_actors_for.empty?
            queries << Arel.sql(<<-SQL, include_actors_for: include_actors_for.map(&:key))
            SELECT
              flipper_gates.name AS name,
              flipper_gates.value AS value,
              flipper_features.name AS feature_name
            FROM flipper_gates
            INNER JOIN flipper_features ON flipper_features.id = flipper_gates.flipper_feature_id
            WHERE flipper_features.name IN (:include_actors_for)
            SQL
          end

          if exclude_actors_for.any?
            NON_ACTOR_GATE_KEYS.each do |gate_key|
              queries << Arel.sql(<<-SQL, exclude_actors_for: exclude_actors_for.map(&:key), gate_key: gate_key)
                SELECT
                  flipper_gates.name AS name,
                  flipper_gates.value AS value,
                  flipper_features.name AS feature_name
                FROM flipper_gates
                INNER JOIN flipper_features ON flipper_features.id = flipper_gates.flipper_feature_id
                WHERE flipper_features.name IN (:exclude_actors_for)
                  AND (flipper_gates.name = :gate_key)
              SQL
            end
          end

          if queries.present?
            sql = queries.inject { |query1, query2| query1 + Arel.sql("UNION ALL") + query2 }
            results = ApplicationRecord::Domain::Features.connection.select_rows(sql)
          else
            results = []
          end
          grouped_db_gates = results.group_by { |_, _, feature_name| feature_name }
          result = {}
          features.each do |feature|
            result[feature.key] = result_for_feature(feature, grouped_db_gates[feature.key])
          end
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          GitHub.dogstats.distribution("flipper.adapter.mysql.duration", duration, tags: tags)
          result
        end
      end

      # Public: Gets the values for all gates for all features.
      #
      # features - an Array of Flipper::Feature's
      #
      # Returns a Hash of Hashes (gate key => gate value(s)).
      def get_all
        ActiveRecord::Base.connected_to(role: :reading) do
          db_gates = Arel.sql <<-SQL
            SELECT
              flipper_gates.name AS name,
              flipper_gates.value AS value,
              flipper_features.name AS feature_name
            FROM flipper_features
            LEFT JOIN flipper_gates ON flipper_gates.flipper_feature_id = flipper_features.id
          SQL
          unless @exclude_actors_for.empty?
            db_gates += Arel.sql <<-SQL, exclude_actors_for: @exclude_actors_for, actor: ACTOR_GATE_KEY
              AND (flipper_features.name NOT IN (:exclude_actors_for) OR flipper_gates.name <> :actor)
            SQL
          end
          grouped_db_gates = ApplicationRecord::Domain::Features.connection.select_rows(db_gates).group_by { |_, _, feature_name| feature_name }
          result = Hash.new do |hash, key|
            hash[key] = result_for_feature(Flipper::Feature.new(key, self), [])
          end
          grouped_db_gates.each_key do |key|
            feature = Flipper::Feature.new(key, self)
            result[feature.key] = result_for_feature(feature, grouped_db_gates[feature.key])
          end
          result
        end
      end

      # Public: enable a gate for a thing
      #
      # feature - The Flipper::Feature for the gate.
      # gate - The Flipper::Gate to disable.
      # thing - The Flipper::Type being disabled for the gate.
      #
      # Returns true
      def enable(feature, gate, thing)
        feature_id = feature_id(feature)
        binds = {
          feature_id: feature_id,
          name: gate.key.to_s,
          value: thing.value.to_s,
        }
        ::FlipperFeature.transaction do
          enforce_optimistic_concurrency(feature_id, feature)

          case gate.data_type
          when :boolean
            clear(feature)
          when :integer
            ApplicationRecord::Domain::Features.connection.delete(Arel.sql(<<-SQL, **binds))
              DELETE FROM flipper_gates
              WHERE
                flipper_gates.flipper_feature_id = :feature_id AND
                flipper_gates.name = :name
            SQL
          when :set
          else
            unsupported_data_type gate.data_type
          end

          gate_exists = ApplicationRecord::Domain::Features.connection.select_value(Arel.sql(<<-SQL, **binds))
            SELECT EXISTS (SELECT * FROM flipper_gates WHERE flipper_feature_id = :feature_id AND name = :name AND value = :value LIMIT 1)
          SQL

          if gate_exists == 0
            if gate.class == Flipper::Gates::Actor
              actor_gate_count = ApplicationRecord::Domain::Features.connection.select_value(Arel.sql(<<-SQL, **binds))
               SELECT COUNT(*) FROM flipper_gates WHERE flipper_feature_id = :feature_id AND name = "actors"
              SQL
              if actor_gate_count >= actor_gate_limit
                GitHub.dogstats.increment("gh.flipper.adapters.mysql.actor_limit_reached", tags: ["feature:#{feature.key}"])
                raise ActorGateLimitError.new("Actor gate limit of #{actor_gate_limit} reached for feature #{feature.key}. For more information on this new limit, see https://github.com/github/delivery-org/discussions/4413#discussion-6916864")
              end
            end

            ApplicationRecord::Domain::Features.connection.insert(Arel.sql(<<-SQL, **binds))
              INSERT INTO
                flipper_gates (flipper_feature_id, name, value, created_at, updated_at)
              VALUES
                (:feature_id, :name, :value, NOW(), NOW())
            SQL
          else
            ApplicationRecord::Domain::Features.connection.update(Arel.sql(<<-SQL, **binds))
              UPDATE flipper_gates
              SET updated_at = NOW()
              WHERE flipper_feature_id = :feature_id
              AND name = :name
              AND value = :value
            SQL
          end

          @forwarder_service.enable_gate(feature.key.to_s, gate.key.to_s, thing.value.to_s) if enable_forwarder
          update_rollout_timestamp(feature, throttle_writes: FeatureFlag.vexi.enabled?(:throttle_flipper_rollout_touch, default: false))
        end

        true
      end

      # Public: Disables a gate for a given thing.
      #
      # feature - The Flipper::Feature for the gate.
      # gate - The Flipper::Gate to disable.
      # thing - The Flipper::Type being disabled for the gate.
      #
      # Returns true.
      def disable(feature, gate, thing)
        feature_id = feature_id(feature)
        binds = {
          feature_id: feature_id,
          name: gate.key.to_s,
          value: thing.value.to_s,
        }
        ::FlipperFeature.transaction do
          enforce_optimistic_concurrency(feature_id, feature)

          case gate.data_type
          when :boolean
            clear(feature)
          when :integer
            ApplicationRecord::Domain::Features.connection.delete(Arel.sql(<<-SQL, **binds))
              DELETE FROM flipper_gates
              WHERE
                flipper_gates.flipper_feature_id = :feature_id AND
                flipper_gates.name = :name
            SQL

            ApplicationRecord::Domain::Features.connection.insert(Arel.sql(<<-SQL, **binds))
              INSERT INTO
                flipper_gates (flipper_feature_id, name, value, created_at, updated_at)
              VALUES
                (:feature_id, :name, :value, NOW(), NOW())
            SQL
          when :set
            ApplicationRecord::Domain::Features.connection.delete(Arel.sql(<<-SQL, **binds))
              DELETE FROM flipper_gates
              WHERE
                flipper_gates.flipper_feature_id = :feature_id AND
                flipper_gates.name = :name AND
                flipper_gates.value = :value
            SQL
          else
            unsupported_data_type gate.data_type
          end

          @forwarder_service.disable_gate(feature.key.to_s, gate.key.to_s, thing.value.to_s) if enable_forwarder
          update_rollout_timestamp(feature, throttle_writes: FeatureFlag.vexi.enabled?(:throttle_flipper_rollout_touch, default: false))
        end

        true
      end

      # Public. Look up a feature value for the given actor.
      def feature_enabled?(feature_key, actor_id)
        GitHub.dogstats.increment("flipper.adapter.mysql.count", tags: ["caller:feature_enabled?"])

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        tags = ["caller:feature_enabled?", "feature:#{feature_key}"]
        ActiveRecord::Base.connected_to(role: :reading) do
          binds = {
            feature_name: feature_key,
            gate_name: "actors",
            value: actor_id,
          }
          value = ApplicationRecord::Domain::Features.connection.select_value(Arel.sql(<<-SQL, **binds))
            SELECT 1
            FROM flipper_gates
            INNER JOIN flipper_features ON flipper_features.id = flipper_gates.flipper_feature_id
            WHERE
              flipper_features.name = :feature_name AND
              flipper_gates.name = :gate_name AND
              flipper_gates.value = :value
          SQL
          result = value.present?
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          GitHub.dogstats.distribution("flipper.adapter.mysql.duration", duration, tags: tags)
          result
        end
      end

      def actors_value(feature_key)
        ActiveRecord::Base.connected_to(role: :reading) do
          binds = {
            name: feature_key.to_s,
            actor: ACTOR_GATE_KEY,
          }
          db_gates = Arel.sql <<-SQL, **binds
            SELECT flipper_gates.value AS value
            FROM flipper_gates
            INNER JOIN flipper_features ON flipper_features.id = flipper_gates.flipper_feature_id
            WHERE flipper_features.name = :name
              AND flipper_gates.name = :actor
          SQL
          ApplicationRecord::Domain::Features.connection.select_values(db_gates).flatten
        end
      end

      def actor_gate_limit
        10000
      end

      private

      # Private: Find a persisted feature by the "feature.key", and return the
      # id. If the feature does not exist, create it.
      #
      # Returns the Integer id
      def feature_id(feature)
        feature_id = ApplicationRecord::Domain::Features.connection.select_value(Arel.sql(<<-SQL, name: feature.key.to_s))
          SELECT id FROM flipper_features WHERE name = :name LIMIT 1
        SQL

        return feature_id unless feature_id.nil?

        # connection.insert returns the last insert ID
        id = ApplicationRecord::Domain::Features.connection.insert(Arel.sql(<<-SQL, name: feature.key.to_s))
          INSERT INTO flipper_features (name, created_at, updated_at)
          VALUES (:name, NOW(), NOW())
        SQL
        @forwarder_service.create_feature_flag(feature.key.to_s) if enable_forwarder
        id
      end

      # Private: Updates the rollout updated at field for the provided flag and marks the exclusion rule as null so the change is sent to the feature flag hub.
      def update_rollout_timestamp(feature, throttle_writes: false)
        if throttle_writes
          ApplicationRecord::Domain::Features.connection.update(Arel.sql(<<-SQL, name: feature.name))
            UPDATE flipper_features
            SET rollout_updated_at = NOW(), exclusion_rule = NULL, updated_at = NOW()
            WHERE name = :name AND (
              rollout_updated_at < NOW() - INTERVAL 1 SECOND
              OR updated_at < NOW() - INTERVAL 1 SECOND
              OR exclusion_rule IS NOT NULL
            )
          SQL
        else
          ApplicationRecord::Domain::Features.connection.update(Arel.sql(<<-SQL, name: feature.name))
            UPDATE flipper_features SET rollout_updated_at = NOW(), exclusion_rule = NULL, updated_at = NOW() WHERE name = :name
          SQL
        end
      end

      # Private: Convert gate rows from the database to the flipper gate hash.
      #
      # Returns Hash of gate key => gate value.
      def result_for_feature(feature, db_gates)
        db_gates ||= []
        db_gates_by_name = db_gates.group_by { |row| row[0] }

        result = {}
        feature.gates.each do |gate|
          result[gate.key] =
            case gate.data_type
            when :boolean, :integer
              rows = db_gates_by_name[gate.key.to_s]
              if rows && rows[0]
                rows[0][1]
              end
            when :set
              rows = db_gates_by_name[gate.key.to_s] || []
              values = rows.map { |row| row[1] }
              values.to_set
            else
              unsupported_data_type gate.data_type
            end
        end
        result
      end

      # Private
      def unsupported_data_type(data_type)
        raise "#{data_type} is not supported by this adapter"
      end

      # Private
      def exclude_actors?(feature)
        @exclude_actors_for.include?(feature.key)
      end

      # Private: Checks the rollout_updated_at property to see if the feature has been
      # modified since the last time we checked it. If it has, we raise an exception
      def enforce_optimistic_concurrency(feature_id, feature)
        if feature.should_compare_etag
          current_rollout_updated_at = ApplicationRecord::Domain::Features.connection.select_value(Arel.sql(<<-SQL, id: feature_id))
            SELECT rollout_updated_at FROM flipper_features WHERE id = :id LIMIT 1
          SQL

          if current_rollout_updated_at != feature.rollout_updated_at
            GitHub.dogstats.increment("flipper.adapter.mysql.optimistic_concurrency_violation.count", tags: ["feature:#{feature.key}"])
            raise ConcurrencyError.new("Outdated Flipper Feature: rollout_updated_at does not match current rollout_update_at in the database")
          end
        end
      end
    end
  end
end
