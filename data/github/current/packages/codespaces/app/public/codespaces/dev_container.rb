# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "json5"
require "forwardable"
module Codespaces
  class DevContainer
    extend Forwardable
    extend GitHub::ResilienceMixin
    include GitHub::ResilienceMixin
    include GitHub::Memoizer

    NESTED_PATH = [".devcontainer", "devcontainer.json"]
    TOP_LEVEL_PATH = [".devcontainer.json"]
    PATHS = [NESTED_PATH.join("/"), TOP_LEVEL_PATH.join("/")]

    GRPC_ERRORS = [GitRPC::NoSuchPath, GitRPC::ObjectMissing, GitRPC::InvalidObject, GitRPC::InvalidRepository, GitHub::Spokes::ClientError, GitRPC::InvalidFullOid]
    PARSER_ERRORS = [SyntaxError, NoMethodError, TypeError]
    VALID_DEVCONTAINER_PATH_GLOB = /\A\.devcontainer(?:(?:\/(?:[\w\-\.\'\"][\w\-\.\'\"\s]{0,62}[\w\-\.\'\"]|[\w\-\.\'\"]))?\/devcontainer)?\.json\z/

    class ReadError < Codespaces::Error; end
    class ParseError < Codespaces::Error; end

    attr_reader :filepath

    def initialize(repository:, oid:, filepath: nil, user: nil, is_prebuild: false)
      @repository = repository
      @oid = oid
      @filepath = filepath
      @user = user
      @is_prebuild = is_prebuild
    end

    def exists?
      parsed_dev_container.any?
    end

    def [](key)
      respond_to?(key) ? public_send(key) : parsed_dev_container[key]
    end

    def codespaces
      return @codespaces if defined?(@codespaces)

      parsed_codespaces_config = parsed_dev_container.dig("customizations", "codespaces") || parsed_dev_container["codespaces"] # parsed_dev_container["codespaces"] is deprecated
      @codespaces = DevContainerConfig::Codespaces.from_hash(@repository, @user, parsed_codespaces_config, is_prebuild: @is_prebuild)
    end

    def dig(*keys)
      parsed_dev_container&.dig(*keys)
    end

    def all_repository_permissions
      codespaces.all_repository_permissions
    end

    def repository_permissions
      codespaces.repository_permissions
    end

    def unknown_repository_permissions
      codespaces.unknown_repository_permissions
    end

    def has_custom_permissions?
      codespaces.has_custom_permissions?
    end

    def validate_repository_permissions_for_user
      codespaces.validate_repository_permissions_for_user
    end

    def diff_all_permissions(prebuild_configuration_id: nil)
      @diff_all_permissions ||= codespaces.diff_allowed_permissions(
        permissions: repository_permissions.merge(all_repository_permissions),
        prebuild_configuration_id: prebuild_configuration_id
      )
    end

    def diff_all_repository_permissions
      @diff_all_repository_permissions ||= codespaces.diff_allowed_permissions(
        permissions: all_repository_permissions
      )
    end

    def diff_repository_permissions(prebuild_configuration_id: nil)
      @diff_repository_permissions ||= codespaces.diff_allowed_permissions(
        permissions: repository_permissions,
        prebuild_configuration_id: prebuild_configuration_id
      )
    end

    def permissions_need_allowance?
      # Always prompt if the user *only* has unknown permissions
      return true if unknown_repository_permissions.present? && all_repository_permissions.blank? && repository_permissions.blank?

      custom_permissions = diff_all_permissions
      custom_permissions.unconsented.present? || custom_permissions.revoked.present?
    end

    def permissions_accepted?
      !permissions_need_allowance?
    end

    def permissions_valid?
      return true if repository_permissions.empty?

      # verify each permission value is 'read' or 'write'
      repository_permissions.values.each do |permissions|
        permissions.values.each do |permission|
          return false unless %w[read write].include?(permission)
        end
      end
      true
    end

    def host_requirements
      @host_requirements ||= HostRequirements.from_hash(parsed_dev_container["hostRequirements"])
    end

    def build
      @build ||= BuildConfig.from_hash(parsed_dev_container["build"])
    end

    memoize def image
      parsed_dev_container["image"]
    end

    def tree_entry
      return @tree_entry if defined?(@tree_entry)
      parsed_dev_container
      @tree_entry
    end

    def self.any_devcontainers?(repository)
      Cache.new(repository).any_devcontainers?
    end

    def self.list_dev_containers(repository, oid)
      return [] unless repository
      return [] unless oid

      with_database_error_fallback(fallback: []) do
        begin
          _, devcontainer_entries = repository.tree_entries(oid, ".devcontainer", limit: nil, recursive: true)
          # devcontainer_entries will contain all files within .devcontainer
          # prune the listing down to only the non-default devcontainer.json files
          devcontainer_configs = devcontainer_entries.filter_map { |entry| entry.path if entry.path.match(VALID_DEVCONTAINER_PATH_GLOB) }
        rescue *GRPC_ERRORS
          devcontainer_configs = []
        end

        devcontainers = []

        devcontainer_configs.sort.prepend(*PATHS).uniq.filter_map do |path|
          raw_devcontainer = begin
            repository.tree_entry(oid, path)
          rescue *GRPC_ERRORS
            next
          end

          begin
            devcontainer = JSON5.parse(raw_devcontainer.data)
            devcontainer_name = devcontainer["name"] if devcontainer
            devcontainers << DevContainerEntry.new(path: path, name: devcontainer_name)
          rescue *PARSER_ERRORS
            next
          end
        end

        # We _could_ do this like RepositoryPreferredFiles by scheduling a job on push but
        # this is probably fine for now given the incredibly tiny overhead of calling this. Only update when listing
        # for the repo's default_oid.
        if GitHub.flipper[:codespaces_devcontainer_caching].enabled?(repository) && oid == repository.default_oid
          Cache.new(repository).has_devcontainers = devcontainers.any?
        end

        devcontainers
      end
    end

    # returns path .devcontainer.json or .devcontainer/devcontainer.json if it exists, nil otherwise
    def self.get_default_path(repository, oid)
      return nil unless repository
      return nil unless oid

      default_path = Codespaces::DevContainer.list_dev_containers(repository, oid)&.first&.path
      return default_path if default_path.present? && is_default_path?(default_path)
    end

    # Is the provided path one of our two "default" devcontainer.json path options.
    def self.is_default_path?(path)
      PATHS.include?(path)
    end

    class Cache
      BASE_KV_KEY = "codespaces:devcontainer:"

      def initialize(repository)
        @repository = repository
      end

      # Checks cache to see if we think there are any devcontainers for the provided repository. This is NOT A
      # GUARANTEE that the repository actually has a devcontainer, but it's a much quicker check than calling
      # list_dev_containers.
      def any_devcontainers?
        # We're using existance to determine if there are any devcontainers in an effort to conserve space in KV. We
        # don't want to pollute it with millions of false values for the minority of repositories that have devcontainers
        # at this point. If there's an error we default to assuming the repo has devcontainers.
        Codespaces::Kv.store.exists(cache_key).value { true }
      end

      def has_devcontainers=(has_devcontainers)
        ActiveRecord::Base.connected_to(role: :writing) do
          if has_devcontainers
            # We only need to set this once
            Codespaces::Kv.store.set(cache_key, Time.now.utc.iso8601) unless any_devcontainers?
          else
            Codespaces::Kv.store.del(cache_key)
          end
        end
      end

      private

      def cache_key
        BASE_KV_KEY + @repository.id.to_s
      end
    end

    class DevContainerEntry
      attr_reader :path, :name

      def initialize(path:, name: nil)
        @path = path
        @name = name
      end

      def display_name
        return @name if @name.present?

        if Codespaces::DevContainer.is_default_path?(@path)
          "Default project configuration"
        else
          @path.split("/")[1...-1].join(" ").underscore.humanize
        end
      end
    end

    def self.valid_path_or_nil(path)
      return nil unless path.is_a?(String)
      path.match(VALID_DEVCONTAINER_PATH_GLOB) ? path : nil
    end

    def self.valid_path?(path)
      self.valid_path_or_nil(path) ? true : false
    end

    private

    def parsed_dev_container
      @parsed_dev_container ||= parse
    end

    def parse
      with_database_error_fallback(fallback: {}) do
        # path being anything but nil means we're looking for a specific file
        # throw errors if the file doesn't exist or is invalid
        if filepath.present?
          raise ReadError, "Provided devcontainer path must be valid string location to a devcontainer.json file" unless filepath.match(VALID_DEVCONTAINER_PATH_GLOB)

          @tree_entry = begin
            @repository.tree_entry(@oid, filepath)
          rescue GitRPC::NoSuchPath
            raise ReadError, "#{filepath} does not exist in this repository"
          rescue *GRPC_ERRORS
            raise ReadError, "Unable to read #{filepath} in this repository"
          end

          raise ReadError.new("#{filepath} is not a valid devcontainer.json file") unless @tree_entry&.data

          devcontainer = begin
            JSON5.parse(@tree_entry.data)
          rescue *PARSER_ERRORS => e
            # If this is a codespace request, we will continue the call to the agent where the codespaces
            # will be created using the Recovery container.
            GitHub.logger.error(
              :exception => e,
              "code.namespace" => "Codespaces::DevContainer",
              "code.function" => "parse",
              "gh.codespaces.devcontainer_path" => filepath,
              "gh.repo.name_with_owner" => @repository.name_with_display_owner,
              "gh.user.login" => @user&.display_login,
            )
            {}
          end

          return devcontainer
        end

        if GitHub.flipper[:codespaces_devcontainer_annoted_tag_fix].enabled?(@user)
          if tag_ref = @repository.tags.detect { |ref| ref.target_oid == @oid }
            # If this is an annotated tag, we can't read the .devcontainer file from the tag itself.
            # Instead, we need to read the .devcontainer file from the commit that the tag points to.
            @oid = tag_ref.commit.oid
          end
        end
        # path being nil means use default behavior
        @tree_entry = PATHS.lazy.filter_map do |path|
          begin
            @repository.tree_entry(@oid, path)
          rescue GitRPC::InvalidObject => ex
            ::Codespaces::ErrorReporter.report(ex) if GitHub.flipper[:codespaces_devcontainer_annoted_tag_fix].enabled?(@user)
          rescue *GRPC_ERRORS
            nil
          end
        end.first || nil
        return {} unless @tree_entry&.data

        devcontainer = begin
          JSON5.parse(@tree_entry.data)
        rescue *PARSER_ERRORS
          {}
        end

        devcontainer
      end
    end

    # TODO: potentially move to DevContainerConfig module
    class HostRequirements
      attr_reader :cpus, :gpus, :memory, :storage

      def initialize(cpus, gpus, memory, storage)
        @cpus = cpus
        @gpus = gpus
        @memory = memory
        @storage = storage
      end

      def self.from_hash(h)
        return blank_host_requirements unless h
        cpus = h["cpus"].to_i || 0
        gpus = h["gpus"].to_i || 0
        memory = size_string_to_bytes(h["memory"])
        storage = size_string_to_bytes(h["storage"])

        new(cpus, gpus, memory, storage)
      end

      class << self
        private

        # This expects strings like: 32mb, 64gb, etc.
        # if we fail to parse a number of bytes out of the string, 0 is returned
        def size_string_to_bytes(s)
          return 0 unless s
          match = s.match(/(\d+)(\w*)/)
          return 0 unless match
          num = match[1].to_i
          return 0 unless num > 0
          case match[2].downcase
          when "kb"
            num.kilobytes
          when "mb"
            num.megabytes
          when "gb"
            num.gigabytes
          when "tb"
            num.terabytes
          else
            0
          end
        end

        def blank_host_requirements
          new(0, 0, 0, 0)
        end
      end
    end

    class BuildConfig
      attr_reader :dockerfile

      def initialize(dockerfile)
        @dockerfile = dockerfile
      end

      def self.from_hash(b)
        return blank_build_config unless b
        dockerfile = b["dockerfile"].to_s

        new(dockerfile)
      end

      def self.blank_build_config
        new("")
      end
    end
  end
end
