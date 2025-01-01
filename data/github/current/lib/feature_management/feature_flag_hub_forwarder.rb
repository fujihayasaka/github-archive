# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagHubForwarder
    MYSQL_FORWARDER_CACHE_KEY = "flipper_mysql_adapter_forwarder_enabled"
    MAX_CONCURRENCY_ATTEMPTS = 5
    TELEMETRY_PREFIX = "gh.feature_management.forwarder"

    sig { void }
    def initialize
      if GitHub.feature_management_feature_flag_hub_mgmt_hmac_key.nil?
        raise FeatureManagement::FeatureFlagHubClientError.new(:environment_error, "Hmac key cannot be nil")
      end
      if GitHub.feature_management_feature_flag_hub_url.nil?
        raise FeatureManagement::FeatureFlagHubClientError.new(:environment_error, "Feature Flag Hub url cannot be nil")
      end
    end

    sig { returns(FeatureManagement::FeatureFlagHubFeatureManagementClient) }
    def feature_management_client
      @feature_management_client ||= T.let(FeatureManagement::FeatureFlagHubFeatureManagementClient.new, T.nilable(FeatureManagement::FeatureFlagHubFeatureManagementClient))
    end

    sig { returns(FeatureManagement::FeatureFlagHubSegmentMemberManagementClient) }
    def segment_member_management_client
      @segment_member_management_client ||= T.let(FeatureManagement::FeatureFlagHubSegmentMemberManagementClient.new, T.nilable(FeatureManagement::FeatureFlagHubSegmentMemberManagementClient))
    end

    # is_disabled? will look to see if "true" is stored in GitHub KV for the specified key, if it is it enables the forwarder.
    sig { params(feature_name: String).returns(T::Boolean) }
    def is_disabled?(feature_name)
      return false if GitHub.use_fm_lite?
      forwarder_disabled = FeatureManagement::Kv.store.get(FeatureManagement::FeatureFlagHubForwarder::MYSQL_FORWARDER_CACHE_KEY).value!.nil?
      forwarder_disabled == true # for sorbet help
    end

    sig { params(feature_name: String).void }
    def create_feature_flag(feature_name)
      return nil if is_disabled?(feature_name)
      begin
        execution_tracing_id = SecureRandom.uuid
        GitHub.logger.with_named_tags({ "feature_flag.key" => feature_name, "#{TELEMETRY_PREFIX}.execution.request" => "create", "#{TELEMETRY_PREFIX}.execution.traceid" => execution_tracing_id }) do
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "sql_commit" })
          f = FeatureManagement::Management::FeatureFlag.new(feature_name)
          op = feature_management_client.create_feature_flag(f)
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "hub_commit" })
        end
      rescue Faraday::ConnectionFailed => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_create.count", tags: ["feature_flag:#{feature_name}", "failure_reason:connection_failed"])
      rescue Faraday::TimeoutError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_create.count", tags: ["feature_flag:#{feature_name}", "failure_reason:timeout"])
      rescue FeatureManagement::FeatureFlagHubAsyncOperationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_create.count", tags: ["feature_flag:#{feature_name}", "failure_reason:status_code_#{e.status_code}"])
      rescue FeatureManagement::FeatureFlagHubValidationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_create.count", tags: ["feature_flag:#{feature_name}", "failure_reason:validation_error", "validation_message:#{e.message}"])
      rescue FeatureManagement::FeatureFlagHubClientError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_create.count", tags: ["feature_flag:#{feature_name}", "failure_reason:client_error"]) if e.code != :async_timeout
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_create.count", tags: ["feature_flag:#{feature_name}", "failure_reason:async_timeout"]) if e.code == :async_timeout
      end
    end

    sig { params(feature_name: String).void }
    def delete_feature_flag(feature_name)
      return nil if is_disabled?(feature_name)
      begin
        execution_tracing_id = SecureRandom.uuid
        GitHub.logger.with_named_tags({ "feature_flag.key" => feature_name, "#{TELEMETRY_PREFIX}.execution.request" => "delete", "#{TELEMETRY_PREFIX}.execution.traceid" => execution_tracing_id }) do
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "sql_commit" })
          feature_management_client.delete_feature_flag(feature_name)
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "hub_commit" })
        end
      rescue Faraday::ConnectionFailed => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_delete.count", tags: ["feature_flag:#{feature_name}", "failure_reason:connection_failed"])
      rescue Faraday::TimeoutError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_delete.count", tags: ["feature_flag:#{feature_name}", "failure_reason:timeout"])
      rescue FeatureManagement::FeatureFlagHubAsyncOperationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_delete.count", tags: ["feature_flag:#{feature_name}", "failure_reason:status_code_#{e.status_code}"])
      rescue FeatureManagement::FeatureFlagHubValidationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_delete.count", tags: ["feature_flag:#{feature_name}", "failure_reason:validation_error", "validation_message:#{e.message}"])
      rescue FeatureManagement::FeatureFlagHubClientError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_delete.count", tags: ["feature_flag:#{feature_name}", "failure_reason:client_error"]) if e.code != :async_timeout
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_delete.count", tags: ["feature_flag:#{feature_name}", "failure_reason:async_timeout"]) if e.code == :async_timeout
      end
    end

    sig { params(feature_name: String).void }
    def clear_feature_flag_gates(feature_name)
      return nil if is_disabled?(feature_name)
      begin
        execution_tracing_id = SecureRandom.uuid
        GitHub.logger.with_named_tags({ "feature_flag.key" => feature_name, "#{TELEMETRY_PREFIX}.execution.request" => "clear", "#{TELEMETRY_PREFIX}.execution.traceid" => execution_tracing_id }) do
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "sql_commit" })
          concurrency_failure = T.let(false, T::Boolean)
          segment_member_management_client.remove_all_members(feature_name)
          MAX_CONCURRENCY_ATTEMPTS.times do |attempt|
            begin
              f = feature_management_client.get_feature_flag(feature_name)
              node = find_node(f.nodes)
              node.state = FeatureManagement::Management::Node::NODE_DISABLED
              node.percentage_of_actors.enabled = false
              node.percentage_of_actors.value = 0.0
              node.percentage_of_calls.enabled = false
              node.percentage_of_calls.value = 0.0
              node.custom_gates.enabled = false
              node.custom_gates.values = []

              feature_management_client.update_feature_flag(f, "nodes")
              break
            rescue FeatureManagement::FeatureFlagHubPreconditionFailedError => pf
              if attempt == (MAX_CONCURRENCY_ATTEMPTS - 1)
                concurrency_failure = true
                GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_gate_clear.count", tags: ["feature_flag:#{feature_name}", "failure_reason:concurrency_max_attempts"])
              end
            end
          end
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "hub_commit" }) if concurrency_failure == false
        end
      rescue Faraday::ConnectionFailed => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_gate_clear.count", tags: ["feature_flag:#{feature_name}", "failure_reason:connection_failed"])
      rescue Faraday::TimeoutError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_gate_clear.count", tags: ["feature_flag:#{feature_name}", "failure_reason:timeout"])
      rescue FeatureManagement::FeatureFlagHubAsyncOperationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_gate_clear.count", tags: ["feature_flag:#{feature_name}", "failure_reason:status_code_#{e.status_code}"])
      rescue FeatureManagement::FeatureFlagHubValidationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_gate_clear.count", tags: ["feature_flag:#{feature_name}", "failure_reason:validation_error", "validation_message:#{e.message}"])
      rescue FeatureManagement::FeatureFlagHubClientError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_gate_clear.count", tags: ["feature_flag:#{feature_name}", "failure_reason:client_error"]) if e.code != :async_timeout
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_feature_gate_clear.count", tags: ["feature_flag:#{feature_name}", "failure_reason:async_timeout"]) if e.code == :async_timeout
      end
    end

    sig { params(feature_name: String, gate_type: String, gate_value: String).void }
    def enable_gate(feature_name, gate_type, gate_value)
      return nil if is_disabled?(feature_name)
      begin
        execution_tracing_id = SecureRandom.uuid
        GitHub.logger.with_named_tags({ "feature_flag.key" => feature_name, "#{TELEMETRY_PREFIX}.execution.request" => "enable", "#{TELEMETRY_PREFIX}.execution.traceid" => execution_tracing_id }) do
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "sql_commit" })
          concurrency_failure = T.let(false, T::Boolean)
          MAX_CONCURRENCY_ATTEMPTS.times do |attempt|
            begin
              case gate_type
              when "boolean"
                apply_boolean_gate_change(feature_name, true)
              when "percentage_of_actors"
                apply_percentage_of_actors_gate_change(feature_name, gate_value, true)
              when "percentage_of_time"
                apply_percentage_of_time_gate_change(feature_name, gate_value, true)
              when "groups"
                apply_custom_groups_gate_change(feature_name, gate_value, true)
              when "actors"
                segment_member_management_client.add_members(feature_name, [gate_value])
              end
              break
            rescue FeatureManagement::FeatureFlagHubPreconditionFailedError => pf
              if attempt == (MAX_CONCURRENCY_ATTEMPTS - 1)
                concurrency_failure = true
                GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_enable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:concurrency_max_attempts"])
              end
            end
          end
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "hub_commit" }) if concurrency_failure == false
        end
      rescue Faraday::ConnectionFailed => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_enable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:connection_failed"])
      rescue Faraday::TimeoutError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_enable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:timeout"])
      rescue FeatureManagement::FeatureFlagHubAsyncOperationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_enable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:status_code_#{e.status_code}"])
      rescue FeatureManagement::FeatureFlagHubValidationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_enable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:validation_error", "validation_message:#{e.message}"])
      rescue FeatureManagement::FeatureFlagHubClientError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_enable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:client_error"]) if e.code != :async_timeout
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_enable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:async_timeout"]) if e.code == :async_timeout
      end
    end

    sig { params(feature_name: String, gate_type: String, gate_value: String).void }
    def disable_gate(feature_name, gate_type, gate_value)
      return nil if is_disabled?(feature_name)
      begin
        execution_tracing_id = SecureRandom.uuid
        GitHub.logger.with_named_tags({ "feature_flag.key" => feature_name, "#{TELEMETRY_PREFIX}.execution.request" => "disable", "#{TELEMETRY_PREFIX}.execution.traceid" => execution_tracing_id }) do
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "sql_commit" })
          concurrency_failure = T.let(false, T::Boolean)
          MAX_CONCURRENCY_ATTEMPTS.times do |attempt|
            begin
              case gate_type
              when "boolean"
                apply_boolean_gate_change(feature_name, false)
              when "percentage_of_actors"
                apply_percentage_of_actors_gate_change(feature_name, gate_value, false)
              when "percentage_of_time"
                apply_percentage_of_time_gate_change(feature_name, gate_value, false)
              when "groups"
                apply_custom_groups_gate_change(feature_name, gate_value, false)
              when "actors"
                segment_member_management_client.remove_members(feature_name, [gate_value])
              end
              break
            rescue FeatureManagement::FeatureFlagHubPreconditionFailedError => pf
              if attempt == (MAX_CONCURRENCY_ATTEMPTS - 1)
                concurrency_failure = true
                GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_disable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:concurrency_max_attempts"])
              end
            end
          end
          GitHub.logger.info("Feature flag hub forwarder execution trace", { "#{TELEMETRY_PREFIX}.execution.stage" => "hub_commit" }) if concurrency_failure == false
        end
      rescue Faraday::ConnectionFailed => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_disable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:connection_failed"])
      rescue Faraday::TimeoutError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_disable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:timeout"])
      rescue FeatureManagement::FeatureFlagHubAsyncOperationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_disable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:status_code_#{e.status_code}"])
      rescue FeatureManagement::FeatureFlagHubValidationError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_disable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:validation_error", "validation_message:#{e.message}"])
      rescue FeatureManagement::FeatureFlagHubClientError => e
        Failbot.report(e)
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_disable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:client_error"]) if e.code != :async_timeout
        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.failed_disable_gate.count", tags: ["feature_flag:#{feature_name}", "failure_reason:async_timeout"]) if e.code == :async_timeout
      end
    end

    sig { params(feature_name: String, is_enabled: T::Boolean).void }
    def apply_boolean_gate_change(feature_name, is_enabled)
      feature = feature_management_client.get_feature_flag(feature_name)

      segment_member_management_client.remove_all_members(feature_name)
      node = find_node(feature.nodes)
      node.state = FeatureManagement::Management::Node::NODE_SHIPPED if is_enabled
      node.state = FeatureManagement::Management::Node::NODE_DISABLED if !is_enabled
      node.percentage_of_actors.enabled = false
      node.percentage_of_actors.value = 0.0
      node.percentage_of_calls.enabled = false
      node.percentage_of_calls.value = 0.0
      node.custom_gates.enabled = false
      node.custom_gates.values = []
      feature_management_client.update_feature_flag(feature, "nodes")
    end

    sig { params(feature_name: String, value: String, is_enabled: T::Boolean).void }
    def apply_percentage_of_actors_gate_change(feature_name, value, is_enabled)
      feature = feature_management_client.get_feature_flag(feature_name)
      node = find_node(feature.nodes)
      node.percentage_of_actors.enabled = (value.to_f > 0) if is_enabled
      node.percentage_of_actors.value = value.to_f if is_enabled
      node.percentage_of_actors.enabled = false if !is_enabled
      node.percentage_of_actors.value = 0.0 if !is_enabled
      feature_management_client.update_feature_flag(feature, "nodes")
    end

    sig { params(feature_name: String, value: String, is_enabled: T::Boolean).void }
    def apply_percentage_of_time_gate_change(feature_name, value, is_enabled)
      feature = feature_management_client.get_feature_flag(feature_name)
      node = find_node(feature.nodes)
      node.percentage_of_calls.enabled = (value.to_f > 0) if is_enabled
      node.percentage_of_calls.value = value.to_f if is_enabled
      node.percentage_of_calls.enabled = false if !is_enabled
      node.percentage_of_calls.value = 0.0 if !is_enabled
      feature_management_client.update_feature_flag(feature, "nodes")
    end

    sig { params(feature_name: String, value: String, is_enabled: T::Boolean).void }
    def apply_custom_groups_gate_change(feature_name, value, is_enabled)
      feature = feature_management_client.get_feature_flag(feature_name)
      node = find_node(feature.nodes)
      if is_enabled
        node.custom_gates.enabled = true
        if !node.custom_gates.values.include?(value)
          node.custom_gates.values << value
        end
      else
        if node.custom_gates.values.include?(value)
          node.custom_gates.values.delete(value)
        end
        node.custom_gates.enabled = (node.custom_gates.values.length > 0)
      end
      feature_management_client.update_feature_flag(feature, "nodes")
    end

    sig { params(nodes: T::Array[FeatureManagement::Management::Node]).returns(FeatureManagement::Management::Node) }
    def find_node(nodes)
      if GitHub.use_fm_lite? && nodes.length == 1 && node = nodes.first
        return node
      end

      nodes.each do |node|
        return node if node.name == GitHub.feature_management_current_stamp
      end
      raise FeatureManagement::FeatureFlagHubClientError.new(:node_not_found, "could not find node named #{GitHub.feature_management_current_stamp} in feature flag's rollout tree")
    end
  end
end
