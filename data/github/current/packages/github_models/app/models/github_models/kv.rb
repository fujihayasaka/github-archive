# typed: strict
# frozen_string_literal: true

module GitHubModels
  class Kv
    VALID_KEYS = T.let({
      "SAMPLE_BANNER_CLOSED" => 1
    }.freeze, T::Hash[String, Integer])

    OWNER = "github/github_models"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { params(user_id: Integer, repository_id: Integer, key: String, value: String).void }
    def self.set_user_repo_settings(user_id, repository_id, key, value)
      unless VALID_KEYS.key?(key)
        raise ArgumentError, "Invalid key: #{key}"
      end

      key = "userId:#{user_id}_repoId:#{repository_id}__#{key}"
      self.set(key, value)
    end

    sig { params(user_id: Integer, repository_id: Integer).returns(T::Hash[String, T.untyped]) }
    def self.get_user_repo_settings(user_id, repository_id)
      key_prefix = "userId:#{user_id}_repoId:#{repository_id}__"
      result = store.mget_prefix(key_prefix)

      # Remove the prefix from each key in the returned hash
      result.value { {} }.transform_keys do |key|
        key.delete_prefix(key_prefix)
      end
    end

    # Public: Get the key used for a particular user to store their access override for o1 models.
    sig { params(user_id: Integer).returns(String) }
    def self.o1_models_access_override_key_for(user_id)
      "access-o1-models:#{user_id}"
    end

    # Public: Check if the user with the specified database ID should have access to o1 models based on a manual
    # override, regardless of their Copilot subscription.
    sig { params(user_id: Integer).returns(T::Boolean) }
    def self.get_o1_models_access_override(user_id)
      key = o1_models_access_override_key_for(user_id)
      result = store.get(key)
      result.value { "0" } == "1"
    end

    # Public: Set the o1 models access override for a user to indicate whether they should have access to o1 models
    # regardless of their Copilot subscription (true) or not (false). Setting it to false will not stop the user from
    # accessing o1 models if their Copilot subscription allows it.
    sig { params(user_id: Integer, value: T::Boolean).void }
    def self.set_o1_models_access_override(user_id, value)
      key = o1_models_access_override_key_for(user_id)
      store.set(key, value ? "1" : "0")
    end

    sig { params(key: String, value: String).void }
    def self.set(key, value)
      store.set(key, value)
    end

    sig { params(key: String).returns(GitHub::KV::Result) }
    def self.get(key)
      store.get(key)
    end

    sig { params(key: String).void }
    def self.del(key)
      store.del(key)
    end

    sig { returns(GitHub::KV) }
    def self.store
      @kv ||= begin
                cfg = GitHub::KV.config.dup
                cfg.table_name = GitHubModels::Kv::DataStore.table_name

                GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::GitHubModels.connection }
              end
    end
  end
end
