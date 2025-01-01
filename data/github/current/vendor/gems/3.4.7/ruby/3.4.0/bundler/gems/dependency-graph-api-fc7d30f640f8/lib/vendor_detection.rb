require_relative "vendor_regex"

module VendorDetection
  # A manifest is inadvertently vendored when it's a vendored path
  # that isn't a vendored library we're intentionally tracking in the
  # dependency graph
  def self.unsupported_vendored_manifest?(path, filename, manifest_type)
    return false if manifest_type.supported_vendored?

    manifest_path = ManifestPath.new(path, filename, manifest_type)
    manifest_path.vendored?
  end

  # Returns true if the path is considered as vendored.
  def self.vendored_manifest_path?(path)
    VendorRegex::Regex.match?(path)
  end

  class ManifestPath
    attr_reader :path, :manifest_type

    def initialize(path, filename, manifest_type)
      @path = (Pathname.new(path.to_s) + filename.to_s).to_s
      @manifest_type = manifest_type
    end

    def depth
      @depth ||= @path.split("/").count
    end

    def vendored?
      return true if vendored_generic?

      case manifest_type
      when Types::Manifest[:gemspec]
        vendored_rubygems?
      when Types::Manifest[:package_json]
        vendored_npm?
      when Types::Manifest[:setup_py], Types::Manifest[:requirements_txt]
        vendored_pypi?
      else
        false
      end
    end

    def vendored_generic?
      VendorDetection.vendored_manifest_path?(path)
    end

    def vendored_rubygems?
      !!((depth > 2 && path =~ /ruby.*[\d\.]+/) ||
         (depth > 1 && path =~ /plugin|gems\/|\A\.?bundle/))
    end

    def vendored_npm?
      !!(depth > 2 && path =~ /node-modules|\A\.npm|\Apublic|assets|\.apm|\.atom/)
    end

    def vendored_pypi?
      !!(path =~ /venv\/lib|env\/lib/i)
    end
  end
end
