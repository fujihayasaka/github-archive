# typed: true
# frozen_string_literal: true

require "openssl"
require "fileutils"
require "find"

class BootstrapCache
  CACHE_FOLDER = ".bundle/checksums"

  def initialize(path)
    @path = path
    FileUtils.mkdir_p(File.join(path, CACHE_FOLDER))
  end

  def ruby_files_changed?
    !!changes(ruby_files, :find)
  end

  def changes(files = ruby_files, method = :select)
    # Add version file, as when there is a version change, we want to bust the cache.
    files = [version, *files]
    files.send(method) do |cache_dep|
      cache_dep.changed?
    end
  end

  def with_gems_cache(force: false, &blk)
    with_cache(ruby_files, &blk)
  end

  def with_file_cache(file, checksum, &blk)
    file_and_checksum = file_plus_checksum(file, checksum)
    with_cache([file_and_checksum], &blk)
  end

  def with_npm_cache(&blk)
    with_cache([node_version, package_json, node_modules], &blk)
  end

  def with_robots_cache(&blk)
    # Only want this optimisation in development.
    return yield if !GitHub::AppEnvironment.development? && block_given?

    with_cache([robots], &blk)
  end

  def with_opensearch_cache(&blk)
    # Only want this optimisation in development.
    return yield if !GitHub::AppEnvironment.development? && block_given?

    with_cache([opensearch], &blk)
  end

  def with_serviceowners_cache(&blk)
    # NOTE that any new ruby files or new classes in ruby files would technically change the contents of the cache.
    # SERVICEOWNERS and lib/github/generate_service_files.rb and script/generate-service-files.rb are going
    # to be the best indicators that some substantive change happens.
    #
    # config/service-mappings.yaml is excluded because most changes there would not affect the cache,
    # and the ones that would also would mean changes in SERVICEOWNERS, ie renaming a service
    #
    # The primary user experience for this being out of date is the cache things it doesn't have a service
    # so if a user runs into problems with the cache, they can always run the script to fix.
    with_cache([serviceowners_cache_files], &blk)
  end

  def gemfile_ruby_version_checksum
    # This is fine to use here as it's just being used for a GitHub Packages cache key
    # in the same format as other Git commits (i.e. 40 hex characters).
    # rubocop:disable GitHub/InsecureHashAlgorithm
    Digest::SHA1.hexdigest([gemfile, ruby_version].map(&:body).join)
    # rubocop:enable GitHub/InsecureHashAlgorithm
  end

  def with_cache(files)
    files = changes(files)
    unless files.empty?
      yield if block_given?
      write_cache(files)
    end
  end

  def write_cache(files)
    files.each do |cache_dep|
      # don't commit the main version file
      next if cache_dep.body == version.body
      cache_dep.write!
    end
  end

  # write the main checksum version
  # This cannot happen on the `with_cache` method as
  # when this file is changed we want to bust all the
  # caches.
  def commit_version
    version.write!
  end

  # private: return all the Ruby files we cache
  def ruby_files
    [gems, gemfile, ruby_version]
  end

  def ruby_version
    string_checksum "#{ENV["RUBY_NEXT"] ? "next" : "current"}:#{RUBY_VERSION}:#{RUBY_REVISION}", "ruby_version"
  end

  private

  def gemfile
    file_plus_checksum ["Gemfile", gemfile_lock], "gemfile"
  end

  def gemfile_lock
    "Gemfile.lock"
  end

  def gems
    file_plus_checksum "vendor/cache/", "gems"
  end

  def node_version
    file_plus_checksum "config/node-version", "node_version"
  end

  def package_json
    file_plus_checksum ["package.json", "package-lock.json"], "package_json"
  end

  def node_modules
    file_plus_checksum "node_modules/", "node_modules"
  end

  def robots
    file_plus_checksum "script/robots", "robots"
  end

  def opensearch
    file_plus_checksum "script/opensearch", "opensearch"
  end

  def version
    file_plus_checksum "config/bootstrap-version", "version"
  end

  def serviceowners_cache_files
    files = [
      "lib/github/serviceowners/generate_service_files.rb",
      "script/generate-service-files.rb",
      "SERVICEOWNERS",
    ]

    file_plus_checksum files, "serviceowners_cache"
  end

  class CacheDependency
    attr_reader :filenames, :body, :checksum_file

    def initialize(filenames, body, checksum_file)
      @filenames = filenames
      @body = body
      @checksum_file = checksum_file
    end

    def changed?
      if File.exist?(checksum_file)
        stored_checksum = File.read(checksum_file)
        current_checksum = body_hexdigest
        current_checksum != stored_checksum
      else
        true
      end
    end

    def write!
      File.open(checksum_file, "wb") do |fd|
        fd.write(body_hexdigest)
      end
    end

    private

    def body_hexdigest
      OpenSSL::Digest::SHA256.hexdigest(body)
    end
  end

  def file_plus_checksum(filenames, checksum_filename, shallow: false)
    bodies = Array(filenames).map do |filename|
      if filename.end_with?("/")
        shallow ? read_shallow_directory(filename) : read_directory(filename)
      else
        read_file(filename)
      end
    end
    CacheDependency.new(filenames, bodies.join(""), File.join(@path, CACHE_FOLDER, checksum_filename))
  end

  def string_checksum(data, checksum_filename)
    CacheDependency.new([], data, File.join(@path, CACHE_FOLDER, checksum_filename))
  end

  def read_file(file)
    File.read(File.join(@path, file))
  end

  # Private: Calculates the SHA256 of all of the contents of a directory of
  # files. If the directory contains other directories they will be traversed
  # recurseively.
  #
  # directory - The String directory name to process
  #
  # Note: Unlike `read_file`, a SHA256 hex digest is returned instead of the actual
  # directory contents, since the latter would be incredibly memory
  # inefficient.
  #
  # Returns the String hexdigest.
  def read_directory(directory)
    directory_path = File.join(@path, directory)
    sha256 = OpenSSL::Digest::SHA256.new
    Find.find(directory_path) do |gem|
      next if File.directory?(gem)
      next if !File.exist?(gem)
      sha256.file(gem)
    end
    sha256.hexdigest
  end

  def read_shallow_directory(directory)
    directory_path = File.join(@path, directory)
    sha256 = OpenSSL::Digest::SHA256.new

    Dir.entries(directory_path).each do |file|
      full_path = File.join(directory_path, file)
      next if File.directory?(full_path)

      sha256.file(full_path)
    end

    sha256.hexdigest
  end
end
