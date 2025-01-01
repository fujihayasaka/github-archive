module ManifestAdapters
  def self.adapters
    [
      ManifestAdapters::Rubygems::Adapter,
      ManifestAdapters::Npm::Adapter,
      ManifestAdapters::Pip::Adapter,
      ManifestAdapters::Maven::Adapter,
      ManifestAdapters::Nuget::Adapter,
      ManifestAdapters::Composer::Adapter,
      ManifestAdapters::Go::Adapter,
      ManifestAdapters::Actions::Adapter,
      ManifestAdapters::Cargo::Adapter,
      ManifestAdapters::Pub::Adapter,
      ManifestAdapters::Swift::Adapter,
    ]
  end

  # A map of purl types to manifest adapters. Should be kept up to date with
  # self.adapters above, and with the purl types at:
  # https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst
  def self.purl_type_to_adapter
    {
      "gem" => ManifestAdapters::Rubygems::Adapter,
      "npm" => ManifestAdapters::Npm::Adapter,
      "pypi" => ManifestAdapters::Pip::Adapter,
      "maven" => ManifestAdapters::Maven::Adapter,
      "nuget" => ManifestAdapters::Nuget::Adapter,
      "composer" => ManifestAdapters::Composer::Adapter,
      "go" => ManifestAdapters::Go::Adapter,
      "actions" => ManifestAdapters::Actions::Adapter, # not official, but we use it
      "cargo" => ManifestAdapters::Cargo::Adapter,
      "pub" => ManifestAdapters::Pub::Adapter,
    }
  end

  def self.parse(filename:, path:, **args)
    adapter = recognize(filename: filename, path: path)

    adapter.parse(filename: filename, path: path, **args)
  end

  def self.recognize(filename:, path:)
    recognized = recognized_path?(filename: filename, path: path)

    unless recognized
      DependencyGraph.logger.error("manifest not recognized",
        "gh.dependency_graph.manifest.not_recognized_error" => true,
        "gh.dependency_graph.manifest.filename" => filename.inspect,
        "gh.dependency_graph.manifest.path" => path.inspect,
        "gh.dependency_graph.manifest.filename_encoding" => filename&.encoding.to_s,
        "gh.dependency_graph.manifest.path_encoding" => path&.encoding.to_s,
      )
      raise NotRecognizedError.new(filename: filename, path: path)
    end

    recognized
  end

  # Returns the adapter for the given purl type, if any. Returns nil otherwise.
  # Returns nil for a malformed purl.
  def self.from_purl(purl)
    begin
      p = PackageUrls::PackageUrl.from_purl(purl: purl)
      type = p.type
      purl_type_to_adapter[type]
    rescue MalformedPackageUrlError # avoid blowing up the response just because an invalid purl was passed in
      nil
    end
  end

  def self.normalize_path(path:)
    # dependency snapshots can come from Windows platforms (backslashes for paths) as well as Linux
    path&.gsub(/\\/, "/")
  end

  # Some manifest types are only supported by snapshots, so we use this method
  # to match them to a package manager rather than iterating through the
  # manifest adapters. There is no "adapter" for files like these, so take care
  # when using one of these manifest types.
  def self.snapshot_only_package_manager(path)
    nil
  end

  # Helper method to check if our manifest adapters support a specific file
  # Note: if you're calling this in a snapshot-related context where an actual
  # adapter is not needed, you should _also_ check `snapshot_only_package_manager`.
  def self.recognized_path?(filename: nil, path:)
    filename = File.basename(path) unless filename

    adapters.detect do |adapter|
      adapter.test(filename: filename, path: path)
    end
  end

  def self.manifest_type(filename: nil, path:)
    filename = File.basename(path) unless filename
    adapter = recognize(filename: filename, path: path)
    adapter.manifest_type(filename: filename, path: path)
  end

  class NotRecognizedError < GraphQL::ExecutionError
    attr_reader :filename, :path

    def initialize(filename:, path:)
      @filename = filename
      @path     = path
    end

    def message
      # NOTE: Do not include filename or path in this message,
      # as it gets sent to dotcom and can potentially expose PII in Sentry
      "Manifest not recognized."
    end
  end
end

ActiveJob::Serializers.add_serializers ManifestAdapters::ManifestSerializer
