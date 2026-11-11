# typed: false
# frozen_string_literal: true

module PackageRegistry
  class PackageVersion < SimpleDelegator
    LATEST_TAG = "latest"
    INTERNAL_LABEL_PREFIX = "github.internal"

    def initialize(version)
      @version = version
      super
    end

    def version
      @version.name
    end

    def uri
      tag_name.blank? ? "@#{digest}" : ":#{tag_name}"
    end

    def created_at
      epoch_micros = @version.created_at.nanos / 10**3
      Time.at(@version.created_at.seconds, epoch_micros)
    end

    def updated_at
      epoch_micros = @version.updated_at.nanos / 10**3
      Time.at(@version.updated_at.seconds, epoch_micros)
    end

    def deleted_at
      return nil unless @version.deleted_at
      epoch_micros = @version.deleted_at.nanos / 10**3
      Time.at(@version.deleted_at.seconds, epoch_micros)
    end

    def license
      return nil unless metadata

      case @version.ecosystem.downcase.to_sym
      when :container
        metadata.labels&.licenses
      when :npm
        metadata.license
      end
    end

    def metadata
      case @version.ecosystem.downcase.to_sym
      when :container
        @version.containerMetadata
      when :npm
        @version.npmMetadata
      when :rubygems
        @version.rubyGemsMetadata
      when :nuget
        @version.nugetMetadata
      when :maven
        @version.mavenMetadata
      end
    end

    def dependencies
      case @version.ecosystem.downcase.to_sym
      when :npm
        metadata.dependencies.count + metadata.dev_dependencies.count + metadata.peer_dependencies.count + metadata.optional_dependencies.count
      when :rubygems
        metadata.dependencies.count
      else
        0
      end
    end

    def manifest
      metadata.manifest
    end

    def download_count
      @version.try(:download_count) || 0
    end

    def media_type
      metadata.manifest.media_type
    end

    def multi_arch?
      platforms_content.present? && PackageRegistry::ContainerPlatform::MEDIA_TYPES[media_type]
    end

    def deleted?
      deleted_at.present?
    end

    def platforms
      if multi_arch?
        JSON.parse(platforms_content).map(&PackageRegistry::ContainerPlatform)
          .uniq(&:descriptor)
          .sort_by(&:descriptor)
      else
        []
      end
    rescue JSON::ParserError => error
      GitHub.logger.info("code.function": "registry_two_package_view.parse_platforms", "exception.message": error)
      []
    end

    def tags(include_latest: true)
      return metadata.tags.reject { |tag| tag.name == LATEST_TAG } unless include_latest
      metadata.tags
    end

    def labels(exclude_internal: true)
      metadata.labels.all_labels.to_h.tap do |labels|
        if exclude_internal
          labels.delete_if { |name, _value| name.include?(INTERNAL_LABEL_PREFIX) }
        end
      end
    end

    def digest
      metadata&.tag&.digest
    end

    def oci_image_title
      labels["org.opencontainers.image.title"]&.split&.first
    end

    def package_type_label
      labels["com.github.package.type"]
    end

    def package_subtype
      return nil unless @version.ecosystem.downcase.to_sym == :container
      @version.containerMetadata.pkg_subtype
    end

    def aop?
      package_subtype == "actions"
    end

    def manifest_has_layers
      has_layers = true
      manifest&.to_h
      .deep_stringify_keys
      .deep_transform_keys { |key| key.camelize(:lower) }
      .tap do |manifest|
        has_layers = !manifest["layers"].nil? && !manifest["layers"].empty?
      end
      has_layers
    end

    private

    def tag_name
      metadata&.tag&.name
    end

    def platforms_content
      labels(exclude_internal: false)["github.internal.platforms"]
    end
  end
end
