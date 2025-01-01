module SnapshotGenerators
  class Snapshot
    def self.gen_repository
      Rantly { positive_integer }
    end

    def self.gen_manifests
      Rantly {
        len = range(0, 10)
        manifests = array(len) { SnapshotGenerators::Manifest.generate }
        # manifests must be unique by path
        manifests.uniq { |m| m.path }
      }
    end

    def self.generate
      Rantly {
        metadata = SnapshotGenerators::Metadata.generate
        github_repository_id = SnapshotGenerators::Snapshot.gen_repository
        manifests = SnapshotGenerators::Snapshot.gen_manifests

        Snapshots::Snapshot.new(metadata: metadata, github_repository_id: github_repository_id, manifests: manifests, source: :spec)
      }
    end
  end
end
