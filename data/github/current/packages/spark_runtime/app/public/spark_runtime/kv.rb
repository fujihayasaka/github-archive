# typed: strict
# frozen_string_literal: true

module SparkRuntime
  module Kv
    # Create the index for all_keys
    sig do
      params(
        current_user: User,
        owner_login: String,
        database_name: String,
      ).returns(T.nilable(T::Array[String]))
    end
    def self.all_keys(current_user, owner_login, database_name)
      client = SparkRuntime::AcaKvClient.new(current_user, owner_login, database_name)
      aca_response = client.list

      if aca_response.status != 200
        return nil
      end

      if aca_response.value.nil?
        return nil
      end

      data = JSON.parse(aca_response.value)
      all_keys = data.map { |item| item["key"] }
      all_keys
    end

    sig do
      params(
        current_user: User,
        owner_login: String,
        database_name: String,
        key: String,
      ).returns(T.nilable(String))
    end
    def self.read_key(current_user, owner_login, database_name, key)
      client = SparkRuntime::AcaKvClient.new(current_user, owner_login, database_name)
      aca_response = client.get(key)

      if aca_response.status == 200 && aca_response.value
        # read the body as json, and extract the value
        json_response = JSON.parse(aca_response.value)
        return json_response["value"] if json_response.key?("value")
      end

      nil
    end

    sig do
      params(
        current_user: User,
        owner_login: String,
        database_name: String,
        key: String,
        value: String
      ).returns(NilClass)
    end
    def self.write_key(current_user, owner_login, database_name, key, value)
      client = SparkRuntime::AcaKvClient.new(current_user, owner_login, database_name)
      aca_response = client.create_or_update(key, value)

      if aca_response.status == 200
        return
      end

      raise "Failed to write key: #{aca_response.status} #{aca_response.value}"
    end

    sig do
      params(
        current_user: User,
        owner_login: String,
        database_name: String,
        key: String
      ).returns(NilClass)
    end
    def self.delete_key(current_user, owner_login, database_name, key)
      client = SparkRuntime::AcaKvClient.new(current_user, owner_login, database_name)
      aca_response = client.remove(key)

      if aca_response.status == 500
        # the ACA API currently returns a 500 if the key doesn't exist
        # the key doesn't exist, so we can consider it deleted
        # this should be fixed in the ACA API, and it should return a 404
        return
      end

      if aca_response.status == 404
        # the key doesn't exist, so we can consider it deleted
        return
      end

      if aca_response.status == 200
        return
      end

      # Something went wrong
      raise "Failed to delete key: #{aca_response.status} #{aca_response.value}"
    end
  end
end
