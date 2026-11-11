# typed: true
# frozen_string_literal: true

module PackageRegistry
  class ContainerPlatform
    MEDIA_TYPES = {
      "application/vnd.docker.distribution.manifest.list.v2+json" => "docker",
      "application/vnd.oci.image.index.v1+json" => "oci",
    }.freeze

    def self.to_proc
      -> (platform) do
        new(
          os: platform["os"],
          version: platform["os.version"],
          architecture: platform["architecture"],
          digest: platform["digest"],
          variant: platform["variant"]
        )
      end
    end

    attr_reader :os, :version, :architecture, :digest, :variant

    def initialize(os:, version:, architecture:, digest:, variant:)
      @os           = os
      @version      = version
      @architecture = architecture
      @digest       = digest
      @variant      = variant
    end

    def descriptor
      return @descriptor if defined?(@descriptor)

      @descriptor = begin
        out = [os]
        out << version.downcase if version
        out << architecture if architecture
        out << variant if variant
        out.compact.join("/")
      end
    end
  end
end
