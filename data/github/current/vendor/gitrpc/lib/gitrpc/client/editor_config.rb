# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "editor_config"

module GitRPC
  class Client
    # Public: Get combined EditorConfig for blob paths.
    #
    # tree_oid - Root tree OID String
    # paths    - Array of String paths
    # timeout  - Max Integer number of seconds to run for
    #
    # Returns a Hash of String paths to EditorConfig Hash results.
    def fetch_editor_config(tree_oid, paths, timeout: 1.0)
      ensure_valid_full_oid(tree_oid)
      deadline = Time.now.to_f + timeout

      result = {}
      cache_keys = editor_config_keys(tree_oid, paths)
      cached = cache_get_multi(cache_keys.values, backend_method: :fetch_editor_config)
      missing_paths = []

      cache_keys.each do |path, key|
        if config = cached[key]
          result[path] = config
        else
          missing_paths << path
        end
      end

      if missing_paths.any?
        send_message(:fetch_editor_config, tree_oid, missing_paths, deadline).each do |path, config|
          @cache.set(cache_keys[path], config)
          result[path] = config
        end
      end

      result
    end

    # Internal: Build memcache key for tree oid and paths.
    #
    # tree_oid - Root tree OID String
    # paths    - Array of String paths
    #
    # Returns Hash of String paths to String cache keys.
    def editor_config_keys(tree_oid, paths, use_git: nil)
      paths.each_with_object({}) { |path, h| h[path] = editor_config_key(tree_oid, path, use_git:) }
    end

    # Internal: Build memcache key for single tree oid and path.
    #
    # Returns String cache key.
    def editor_config_key(tree_oid, path, use_git: nil)
      ["editor-config", "v3", EditorConfig::VERSION, tree_oid, sha256(path), use_git].join(":")
    end
  end
end
