module DependencyGraph::ObjectModel
  # Why "abstract manifest"? It's a pre-refactoring encapsulation of how the different
  # dependencies we have are different, and it's meant to allow us to write
  # common code (like vulnerability lookup) that can be reused across very different
  # dependency sources (like parsedmanifest, ds-api, etc. )
  class AbstractManifest
    # return dependency adapters for all dependencies in the manifest
    def dependencies
      raise NotImplementedError.new("Abstract method called!")
    end

    # the file path of the manifest
    def file_path
      raise NotImplementedError.new("Abstract method called!")
    end

    # returns the manifest package_manager. This may be phased out eventually as we become less opinionated
    # about manifest level ecosystem awareness (instead opting for dependency level).
    def package_manager
      raise NotImplementedError.new("Abstract method called!")
    end

    # This method is optional, parsed_manifest has its own notion of vendored we're protecting by using this.
    def is_vendored
      false
    end

    # This method is optional, parsed_manifest gets this when parsing but other sources (e.g. DSAPI) do not track it.
    def manifest_type
      nil
    end

    # This method is optional. DS-API provides a name for the manifest, but parsed_manifest does not.
    def name
      nil
    end

    # This method is optional. This is the ID of the snapshot from DS-API that this manifest came from.
    def snapshot_id
      nil
    end

    # This method is optional. This is the detector name of the snapshot from DS-API that this manifest came from.
    def snapshot_detector_name
      nil
    end

    # This method is optional. This is the scanned timestamp of the snapshot from DS-API that this manifest came from.
    def snapshot_scanned
      nil
    end

    # This method is optional, source is overridden in cases where the source is not strictly from dependency graph (usually just snapshots).
    def source
      "dependency graph"
    end

    def to_proto(vulnerabilities_hash_by_dependency, include_relationship: false)
      actual_is_vendored = is_vendored || VendorDetection.vendored_manifest_path?(file_path)
      DependencyGraphAPI::V1::Manifest.new(
        file_path: file_path,
        original_file_path: file_path,
        is_vendored: DependencyGraphAPI::V1::NullableBool.new(value: actual_is_vendored),
        package_manager: package_manager.to_proto,
        type: manifest_type,
        dependencies: dependencies.map { |dependency| dependency.to_proto(vulnerabilities_hash_by_dependency, include_relationship: include_relationship) },
        source: source,
        name: name,
        snapshot_id: snapshot_id
      )
    end

    def self.to_proto(manifests:, lookup_vulnerabilities:, include_relationship: false)
      vulnerabilities = if lookup_vulnerabilities
        DependencyGraph::ObjectModel::DependencyVulnerabilitiesHash.generate_hash(manifests)
      else
        {}
      end

      manifests.map { |manifest| manifest.to_proto(vulnerabilities, include_relationship: include_relationship) }
    end
  end
end
