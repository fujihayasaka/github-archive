# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class OwnerApiKV
    sig do
      params(
        permanent_name: String,
        api_version: String,
      ).void
    end
    def self.set_api_version(permanent_name, api_version)
      ActiveRecord::Base.connected_to(role: :writing) do
        SparkRuntime::KV.store.set(user_api_key(permanent_name), api_version, expires: nil)
      end
    end

    sig do
      params(
        permanent_name: String,
      ).returns(T.nilable(String))
    end
    def self.get_api_version(permanent_name)
      result = SparkRuntime::KV.store.get(user_api_key(permanent_name))
      result.value!
    end

    # Convenience functions for the first API revision
    sig do
      params(
        permanent_name: String,
      ).void
    end
    def self.set_new_api_version(permanent_name)
      set_api_version(permanent_name, "1.1")
    end

    sig do
      params(
        permanent_name: String,
      ).returns(T::Boolean)
    end
    def self.is_new_api_version?(permanent_name)
      result = get_api_version(permanent_name)
      return false if result.nil?
      result == "1.1"
    end

    sig do
      params(
        permanent_name: String,
      ).returns(String)
    end
    private_class_method def self.user_api_key(permanent_name)
      # The key name is scoped with a special tag, followed by the user/owner's permanentName
      "user_api_version:#{permanent_name}"
    end
  end
end
