# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "editor_config"

module GitRPC
  class Backend
    class EditorConfigTimeout < Timeout
    end

    # Internal: Get combined EditorConfig for blob paths.
    #
    #
    # tree_oid - Root tree OID String
    # paths    - Array of String paths
    # deadline - Float unix timestamp to run until
    # use_git  - Use the Git-based backend if enabled
    #
    # TODO: default deadline = nil can be removed one day after this is fully
    # rolled out to all file servers.
    #
    # Returns a Hash of String paths to EditorConfig Hash results.
    def fetch_editor_config(tree_oid, paths, deadline = nil)
      result = {}
      timeout = deadline - Time.now.to_f if deadline

      rdr = T.let(nil, T.nilable(GitRPC::Backend::ObjectReader))
      begin
        self.timeout(timeout, EditorConfigTimeout) do
          rdr = ObjectReader.new(native, nil)
          type = rdr.object(tree_oid, :info)[:type]
          if type != :tree
            raise GitRPC::InvalidObject, "Invalid object type, expected tree but was #{type}"
          end
          cached_config = {}
          paths.each do |path|
            config = EditorConfig.load(path) do |config_path|
              if cached_config.key?(config_path)
                cached_config[config_path]
              else
                obj = rdr.object("#{tree_oid}:#{config_path}", :contents)
                cached_config[config_path] = obj[:type] == :blob ? obj[:data] : nil
              end
            end
            result[path] = EditorConfig.preprocess(config)
          end
        end
      ensure
        rdr&.close
      end

      result
    end
    rpc_reader :fetch_editor_config
  end
end
