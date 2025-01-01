# typed: strict
# frozen_string_literal: true

module SparkRuntime
  module Kv
    class SparkRuntimeKvError < SparkRuntimeError
      sig { returns(Integer) }
      attr_reader :status

      sig { params(message: String, status: Integer).void }
      def initialize(message, status)
        super(message)
        @status = status
      end
    end

    class SparkRuntimeKvReadOnlyError < SparkRuntimeError; end

    # Create the index for all_keys
    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
        region: T.nilable(String)
      ).returns(T.nilable(T::Array[String]))
    end
    def self.all_keys(current_user, runtime_app, region = nil)
      client = self.create_client(current_user, runtime_app, region)
      return nil unless client

      aca_response = client.list

      use_new_errors = FeatureFlag.vexi.enabled?(:spark_api_errors, current_user, default: false)
      if use_new_errors
        if aca_response.status != 200
          raise SparkRuntimeKvError.new("Failed to list keys: #{aca_response.status} #{aca_response.value}", aca_response.status)
        end
      else
        if aca_response.status != 200
          return nil
        end
      end

      if aca_response.value.nil?
        return nil
      end

      data = JSON.parse(aca_response.value)
      all_keys = data.map { |item| item["key"] }
      all_keys
    end

    # Get all values for a specific collection
    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
        collection: String,
        region: T.nilable(String)
      ).returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
    end
    def self.get_all_values_for_collection(current_user, runtime_app, collection, region = nil)
      client = self.create_client(current_user, runtime_app, region)
      return nil unless client

      aca_response = client.list_collection(collection)

      if aca_response.status != 200
        raise SparkRuntimeKvError.new("Failed to list values for collection: #{aca_response.status} #{aca_response.value}", aca_response.status)
      end

      if aca_response.value.nil?
        return nil
      end

      JSON.parse(aca_response.value)
    end

    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
        key: String,
        region: T.nilable(String)
      ).returns(T.nilable(String))
    end
    def self.read_key(current_user, runtime_app, key, region = nil)
      client = self.create_client(current_user, runtime_app, region)
      return nil unless client

      aca_response = client.get(key)

      use_new_errors = FeatureFlag.vexi.enabled?(:spark_api_errors, current_user, default: false)
      if use_new_errors
        should_404_gets = FeatureFlag.vexi.enabled?(:spark_kv_get_404, current_user, default: false)

        if should_404_gets
          if aca_response.status != 200
            raise SparkRuntimeKvError.new("Failed to read key: #{aca_response.status} #{aca_response.value}", aca_response.status)
          end
        else
          if aca_response.status != 404 && aca_response.status != 200
            raise SparkRuntimeKvError.new("Failed to read key: #{aca_response.status} #{aca_response.value}", aca_response.status)
          end
        end
      end

      if aca_response.status == 200 && aca_response.value
        # read the body as json, and extract the value
        json_response = JSON.parse(aca_response.value)
        return json_response["value"] if json_response.key?("value")
      end

      # In all other cases, just return nil
      nil
    end

    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
        key: String,
        value: String,
        region: T.nilable(String)
      ).returns(NilClass)
    end
    def self.write_key(current_user, runtime_app, key, value, region = nil)
      if is_read_only?(current_user, runtime_app)
        GitHub.logger.info("#{current_user.display_login} attempted to write to read-only KV store for #{runtime_app.permanent_name}")
        use_new_errors = FeatureFlag.vexi.enabled?(:spark_api_errors, current_user, default: false)
        if use_new_errors
          raise SparkRuntimeKvReadOnlyError, "Unable to write to read-only KV"
        else
          raise "Unable to write to read-only KV"
        end
      end

      client = self.create_client(current_user, runtime_app, region)
      return unless client

      aca_response = client.create_or_update(key, value)

      if aca_response.status == 200
        return
      end

      use_new_errors = FeatureFlag.vexi.enabled?(:spark_api_errors, current_user, default: false)
      if use_new_errors
        raise SparkRuntimeKvError.new("Failed to write key: #{aca_response.status} #{aca_response.value}", aca_response.status)
      else
        raise "Failed to write key: #{aca_response.status} #{aca_response.value}"
      end
    end

    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
        key: String,
        region: T.nilable(String)
      ).returns(NilClass)
    end
    def self.delete_key(current_user, runtime_app, key, region = nil)
      if is_read_only?(current_user, runtime_app)
        GitHub.logger.info("#{current_user.display_login} attempted to delete from read-only KV store for #{runtime_app.permanent_name}")
        use_new_errors = FeatureFlag.vexi.enabled?(:spark_api_errors, current_user, default: false)
        if use_new_errors
          raise SparkRuntimeKvReadOnlyError, "Unable to delete from read-only KV"
        else
          raise "Unable to delete from read-only KV"
        end
      end

      client = self.create_client(current_user, runtime_app, region)
      return nil unless client

      aca_response = client.remove(key)

      if aca_response.status == 404
        # the key doesn't exist, so we can consider it deleted
        return
      end

      if aca_response.status == 200
        return
      end

      # Something went wrong
      use_new_errors = FeatureFlag.vexi.enabled?(:spark_api_errors, current_user, default: false)
      if use_new_errors
        raise SparkRuntimeKvError.new("Failed to delete key: #{aca_response.status} #{aca_response.value}", aca_response.status)
      else
        raise "Failed to delete key: #{aca_response.status} #{aca_response.value}"
      end
    end

    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp,
        region: T.nilable(String)
      ).returns(T.nilable(SparkRuntime::AcaKvClient))
    end
    def self.create_client(current_user, runtime_app, region = nil)
      SparkRuntime::AcaKvClient.new(current_user, runtime_app, region)
    end

    sig do
      params(
        current_user: User,
        runtime_app: Spark::RuntimeApp
      ).returns(T::Boolean)
    end
    def self.is_read_only?(current_user, runtime_app)
      # If the runtime app has a special KV marker, only allow writes from the owner
      raw_marker = SparkRuntime::KV.store.get("read_only_kv:#{runtime_app.permanent_name}").value { "false" }

      # If the runtime app has read_only_kv set, only allow writes from the owner
      read_only_kv = FeatureFlag.vexi.enabled?(:spark_read_only_kv, current_user, default: false) && runtime_app.read_only_kv
      if raw_marker == "true" || read_only_kv
        runtime_app.user_id != current_user.id
      else
        false
      end
    end

    sig do
      params(
        runtime_app: Spark::RuntimeApp
      ).void
    end
    def self.mark_read_only(runtime_app)
      SparkRuntime::KV.store.set("read_only_kv:#{runtime_app.permanent_name}", "true")
    end
  end
end
