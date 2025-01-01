require "digest"

module Snapshots
  class Snapshot
    include ActiveModel::Serializers::JSON

    attr_reader :metadata, :github_repository_id, :manifests, :source

    class << self
      def from_json(snapshot_record, snapshot_json)
        return nil unless snapshot_record.present?

        manifests = []
        if snapshot_json["manifests"].present?
          manifests = snapshot_json["manifests"].map do |manifest|
            Snapshots::Manifest.new(
              path: manifest["path"],
              oid: manifest["oid"],
              dependencies: manifest["dependencies"].map do |dependency|
                coerced_scope = dependency["scope"].present? ? Types::Scope.coerce(dependency["scope"]) : nil
                Snapshots::Dependency.new(name: dependency["name"], version: dependency["version"], scope: coerced_scope)
              end
            )
          end
        end
        metadata = snapshot_record.metadata

        Snapshots::Snapshot.new(
          metadata: Snapshots::Metadata.new(
            push_id: metadata["push_id"],
            sha:  metadata["sha"],
            ref: metadata["ref"]
          ),
          github_repository_id: snapshot_json["github_repository_id"],
          manifests: manifests,
          source: snapshot_json["source"].present? ? snapshot_json["source"] : snapshot_record.source
        )
      end
    end

    def initialize(metadata:, github_repository_id:, manifests:, source:)
      @metadata = metadata
      @github_repository_id = github_repository_id
      @manifests = manifests
      @source = source
    end

    def attributes
      # In order for to_json `:exclude` filtering to work (non-ActiveRecord class)
      {
        "metadata" => metadata,
        "github_repository_id" => github_repository_id,
        "manifests" => manifests,
        "source" => source
      }
    end

    def deep_clone
      Marshal.load(Marshal.dump(self))
    end

    def to_json(opts = {})
      except = opts[:except].present? ? opts[:except].append(:metadata) : [:metadata]
      super(opts.merge(except: except))
    end

  end
end
