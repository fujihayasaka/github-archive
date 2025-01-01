# typed: strict
# frozen_string_literal: true

require "github/packers"
require "digest"
require "yaml"

module GitHub
  class Serviceowners

    autoload :GenerateServiceFiles, "github/serviceowners/generate_service_files"
    autoload :Tableowners, "github/serviceowners/tableowners"
    autoload :ExternalServices, "github/serviceowners/external_services"
    autoload :Packageowners, "github/serviceowners/packageowners"

    SERVICE_PREFIX = "github"
    UNKNOWN_SERVICE = T.let("#{SERVICE_PREFIX}/unknown".freeze, String)
    CACHE_PATH = T.let(GitHub::AppEnvironment.root.join("vendor").join("serviceowners").join("serviceowners_cache.json").freeze, Pathname)
    CLASS_CACHE_PATH = T.let(GitHub::AppEnvironment.root.join("vendor").join("serviceowners").join("serviceowners_class_cache.json"), Pathname)
    DEFAULT_SERVICE_MAPPINGS_PATH = T.let(GitHub::AppEnvironment.root.join("config", "service-mappings.yaml").to_s.freeze, String)
    DEFAULT_SERVICEOWNERS_PATH = T.let(GitHub::AppEnvironment.root.join("SERVICEOWNERS").to_s.freeze, String)
    OWNERSHIP_PATH = T.let(GitHub::AppEnvironment.root.join("ownership.yaml").to_s.freeze, String)

    NO_REVIEW_LINE_PATTERN = /^[\w\*\.\/\-]+\s+:[\w\-]+\.no_review\n/


    # Returns a (cached) list of all Git-committed files in the GitHub::AppEnvironment.root.
    sig { params(directory: String).returns(T::Set[String]) }
    def self.git_files(directory = ".")
      @git_files ||= T.let(Hash.new do |git_files, key|
        matching_git_files = IO.popen(["git", "-c", "core.quotepath=off",
                                        "ls-files", File.join(GitHub::AppEnvironment.root.to_s, key)])
                      .read
                      .split("\n")
                      .sort
                      .freeze
        git_files[key] = Set.new(matching_git_files)
      end, T.nilable(T::Hash[String, T::Set[String]]))
      @git_files[directory]
    end

    # Loads the SERVICEOWNERS file/services cache and populates an internal hash of paths, classes and services.
    sig { params(cache_hash: T.nilable(T::Hash[String, T::Array[String]])).void }
    def initialize(cache_hash: nil)
      @classes_services = T.let({}, T::Hash[T.nilable(String), Symbol])

      cache_hash ||= begin
        cache_json = GitHub::Serviceowners::CACHE_PATH.read
        GitHub::JSON.decode(cache_json)
      end

      @paths_services = T.let({}, T::Hash[T.nilable(String), Symbol])
      cache_hash.each do |service, files|
        files.each do |file|
          @paths_services[file] = service.to_sym
        end
      end
      @paths_services.freeze

      class_cache_json = GitHub::Serviceowners::CLASS_CACHE_PATH.read
      @classes_services = GitHub::JSON.decode(class_cache_json).map do |key, value|
        [key, value.to_sym]
      end.to_h.freeze

      @caller_attribution_cache = T.let({}, T::Hash[String, T.any(String, Symbol)])

      @service_hashes = T.let(service_names_by_hash, T::Hash[String, String])
    end

    sig { returns(T::Hash[String, T.any(String, Symbol)]) }
    attr_reader :caller_attribution_cache

    # DEPRECATED: class constant lookup is inaccurate
    #
    # https://github.com/github/app-partitioning/issues/171
    #
    # Takes a Ruby class and returns the service that owns it.
    #
    # klass - The class to look up.
    # prefix - Optional "github/" service prefix. Use when a fully-qualified catalog_service name is needed.
    #
    # Returns the service name as a string or nil if the class is not owned by a service.
    sig { params(klass: T.nilable(Object), prefix: T::Boolean).returns(T.any(T.nilable(String), Symbol)) }
    def service_for_class(klass, prefix: false)
      apply_prefix(@classes_services[klass&.to_s], prefix)
    end

    # Takes a file path and returns the service that owns it.
    #
    # path - A GitHub::AppEnvironment.root relative path.
    # prefix - Optional "github/" service prefix. Use when a fully-qualified catalog_service name is needed.
    #
    # Returns the service name as a string or nil if the file is not owned by a service.
    sig { params(path: T.nilable(String), prefix: T::Boolean).returns(T.any(T.nilable(String), Symbol)) }
    def service_for_path(path, prefix: false)
      apply_prefix(@paths_services[path], prefix)
    end

    # Looks up the service name for a given catalog service hash.
    #
    # hash - The salted SHA256 hash of the catalog service name (as exposed in the DOM via meta tag).
    #
    # Uses the hash-to-service-name map built by service_names_by_hash to return the corresponding service name.
    #
    # Returns the fully-qualified service name (e.g., "github/my_service") if found, or nil if the hash does not exist in the map.
    sig { params(hash: String).returns(T.nilable(String)) }
    def service_for_hash(hash)
      @service_hashes[hash]
    end

    private

    sig { params(service: T.nilable(Symbol), prefix: T::Boolean).returns(T.any(T.nilable(String), Symbol)) }
    def apply_prefix(service, prefix)
      service && prefix ? "#{SERVICE_PREFIX}/#{service}" : service
    end

    # Builds a hash mapping of catalog service hashes to their corresponding service names.
    #
    # Reads the catalog service names from the ownership file and hashes each name (using the configured salt).
    # The result is a hash where the key is the salted SHA256 hash of the service name, and the value is the
    # fully-qualified service name (e.g., "github/my_service").
    #
    # This hash can be used to attribute errors or events reported with a service hash back to the owning service.
    #
    # Returns a Hash<String, String> mapping service hash => service name.
    sig { returns(T::Hash[String, String]) }
    def service_names_by_hash
      ownership_yaml = YAML.safe_load(File.read(OWNERSHIP_PATH))
      services = ownership_yaml["ownership"]
      service_names_by_hash = {}
      salt = GitHub::ServiceMapping::HASH_SALT

      unknown = GitHub::Serviceowners::UNKNOWN_SERVICE
      service_names_by_hash[Digest::SHA256.hexdigest("#{salt}#{unknown}")] = unknown

      services.each do |service|
        name = service["name"]
        hash = Digest::SHA256.hexdigest("#{salt}#{name}")
        service_names_by_hash[hash] = name
      end
      service_names_by_hash
    end
  end
end
