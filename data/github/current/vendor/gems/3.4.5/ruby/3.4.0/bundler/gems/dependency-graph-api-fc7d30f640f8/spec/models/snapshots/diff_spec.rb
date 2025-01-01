require "rails_helper"

require "rantly"
require "rantly/shrinks"
require "rantly/rspec_extensions"

def test_dep(name: "test_dependency", version: "1.0.0", scope: "runtime")
  Snapshots::Dependency.new(name: name, version: version, scope: scope)
end

def no_manifest_snapshot
  Snapshots::Snapshot.new(
    metadata: Snapshots::Metadata.new(
      push_id: "123",
      sha: "baddead",
      ref: "main"
      ),
    github_repository_id: "abcdef123",
    manifests: [],
    source: :spec
    )

end

def test_snapshot_with_deps(deps)
  Snapshots::Snapshot.new(
    metadata: Snapshots::Metadata.new(
      push_id: "123",
      sha: "baddead",
      ref: "main"
    ),
    github_repository_id: "abcdef123",
    manifests: [
      Snapshots::Manifest.new(
        path: "package.json",
        oid: "bead",
        dependencies: deps
      )
    ],
    source: :spec
  )
end

def example_snapshot_metadata
  {
    snapshot_id: 3,
    correlator: "build",
    detector: "ruby script",
  }
end

def example_twirp_diff
  Twirp::ClientResp.new(
    data: Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new(
      dependency_changes: [
        Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
          change_type: :ADDED,
          snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
            **example_snapshot_metadata
          ),
          manifest: "package-lock.json",
          ecosystem: "npm",
          name: "jquery",
          version: "2.0.0",
          package_url: "pkg:npm/jquery@2.0.0",
        ),
        Github::DependencySnapshotsApi::GetSnapshotDiffResponse::DependencyChange.new(
          change_type: :REMOVED,
          snapshot_metadata: Github::DependencySnapshotsApi::GetSnapshotDiffResponse::SnapshotMetadata.new(
            **example_snapshot_metadata
          ),
          manifest: "package-lock.json",
          ecosystem: "npm",
          name: "jquery",
          version: "1.0.0",
          package_url: "pkg:npm/jquery@1.0.0",
        )
      ]
    )
  )
end

module Snapshot
  # Monkey-punching some methods in here for easy debugging
  class Snapshot
    def to_h
      manifests = @manifests.map(&:to_h)
      ret = {}
      manifests.each do |manifest|
        ret[manifest[:path]] = manifest[:dependencies]
      end
      ret
    end
  end

  class Manifest
    def to_h
      deps = @dependencies.map do |dep|
        {
          name: dep.name,
          version: dep.version,
          scope: dep.scope
        }
      end
      {
        path: @path,
        oid: @oid,
        dependencies: deps
      }
    end

    # this is actually for testing, since snapshots are generally immutable
    def delete_at(idx)
      @dependencies.delete_at(idx)
    end
  end
end

describe Snapshots::ManifestDependencySet do
  let (:deps_a) {
    [
      test_dep(name: "gets_deleted", version: "1.0.0"),
      test_dep(name: "gets_updated", version: "2.0.0"),
      test_dep(name: "stays_same", version: "3.0.0"),
    ]
  }

  let (:deps_b) {
    [
      test_dep(name: "gets_updated", version: "2.1.0"),
      test_dep(name: "stays_same", version: "3.0.0"),
      test_dep(name: "gets_added", version: "1.0.0"),
    ]
  }
  let (:manifest_a) {
    Snapshots::Manifest.new(
      path: "Gemfile",
      oid: "666bad",
      dependencies: deps_a
      )
  }
  let (:manifest_b) {
    Snapshots::Manifest.new(
      path: "Gemfile",
      oid: "fabb",
      dependencies: deps_b
      )
  }

  let (:set_a) { Snapshots::ManifestDependencySet.new(Snapshots::Snapshot.new(metadata: nil, github_repository_id: nil, source: :spec, manifests: [manifest_a])) }
  let (:set_b) { Snapshots::ManifestDependencySet.new(Snapshots::Snapshot.new(metadata: nil, github_repository_id: nil, source: :spec, manifests: [manifest_b])) }

  describe "#-" do
    it "returns the difference between the two sets" do
      difference = set_a - set_b
      expect(difference.collect.map(&:name).sort).to eq(["gets_deleted", "gets_updated"])

      difference = set_b - set_a
      expect(difference.collect.map(&:name).sort).to eq(["gets_added", "gets_updated"])
    end

    it "provides enough metadata to reconstruct a manifest" do
      difference = set_a - set_b
      manifest_dependency = difference.collect.sort_by(&:key).first
      expect(manifest_dependency.manifest_path).to eq("Gemfile")
      expect(manifest_dependency.name).to eq("gets_deleted")
      expect(manifest_dependency.version).to eq("1.0.0")
      expect(manifest_dependency.scope).to eq("runtime")
    end
  end
end

describe Snapshots::Diff do
  let (:empty_manifest_snapshot) { test_snapshot_with_deps([]) }

  let (:remove_me) { test_dep(name: "remove_me") }
  let (:keep_me) { test_dep(name: "keep_me") }
  let (:add_me) { test_dep(name: "add_me") }

  let (:update_me_1) { test_dep(name: "update_me", version: "1.0.0") }
  let (:update_me_1_0_1) { test_dep(name: "update_me", version: "1.0.1") }
  let (:update_me_2) { test_dep(name: "update_me", version: "2.0.0") }
  let (:update_me_2_0_1) { test_dep(name: "update_me", version: "2.0.1") }
  let (:update_me_3) { test_dep(name: "update_me", version: "3.0.0") }

  describe "#simple_diff" do
    let (:base) { SnapshotGenerators::Snapshot.generate }

    it "returns an empty diff when the snapshots have the same dependencies" do
      property_of {
        SnapshotGenerators::Snapshot.generate
      }.check { |target|
        base = Snapshots::Snapshot.new(
          metadata: target.metadata,
          github_repository_id: target.github_repository_id,
          manifests: target.manifests,
          source: :spec
          )
        diff = Snapshots::Diff.new(base, target).simple_diff
        expect(diff[:added]).to be_empty, "There should be no 'added' dependencies in this diff"
        expect(diff[:removed]).to be_empty, "There should be no 'removed' dependencies in this diff"
      }
    end

    it "correctly identifies a deleted dependency" do
      # Generate a snapshot consisting of 1+ non-empty manifests
      property_of {
        snapshot = SnapshotGenerators::Snapshot.generate
        guard snapshot.manifests.count >= 1 && snapshot.manifests.all? { |m| m.dependencies.count >= 1 }
        snapshot
      }.check { |base|
        # Randomly choose a manifest
        manifest_idx = Rantly { range(0, base.manifests.count - 1) }
        # Randomly choose a dependency in that manifest
        dep_idx = Rantly { range(0, base.manifests[manifest_idx].dependencies.count) - 1 }

        target = base.deep_clone
        deleted = target.manifests[manifest_idx].dependencies.delete_at(dep_idx)

        diff = Snapshots::Diff.new(base, target).simple_diff
        expect(diff[:added]).to be_empty
        expect(diff[:removed])
          .to eq({ "#{base.manifests[manifest_idx].path}" => [deleted] })
      }
    end

    it "correctly identifies an added dependency" do
      property_of {
        SnapshotGenerators::Dependency.generate
      }.check { |dependency|
        target = test_snapshot_with_deps([dependency])
        diff = Snapshots::Diff.new(empty_manifest_snapshot, target).simple_diff
        expect(diff[:removed]).to be_empty
        expect(diff[:added]).to eq({
            empty_manifest_snapshot.manifests.first.path => [dependency]
          })
      }
    end

    it "identifies a changed dependency as both removed and added" do
      old_version = test_dep(name: "updated", version: "1.0.0")
      new_version = test_dep(name: "updated", version: "2.0.0")

      base = test_snapshot_with_deps([old_version])
      target = test_snapshot_with_deps([new_version])

      diff = Snapshots::Diff.new(base, target).simple_diff

      manifest_path = base.manifests.first.path
      expect(diff).to eq({
          removed: { manifest_path => [old_version] },
          added: { manifest_path => [new_version] },
          snapshot_added: [],
          snapshot_removed: [],
        })
    end

    it "handles duplicated dependencies by requiring all copies to be removed to count as a removal" do
      duped = test_dep(name: "duplicated")
      base = test_snapshot_with_deps([duped, duped, duped, test_dep(name: "leave_me")])

      target_remove_one = test_snapshot_with_deps([duped, test_dep(name: "leave_me")])
      target_remove_all = test_snapshot_with_deps([test_dep(name: "leave_me")])

      diff_remove_one = Snapshots::Diff.new(base, target_remove_one).simple_diff
      diff_remove_all = Snapshots::Diff.new(base, target_remove_all).simple_diff

      expect(diff_remove_one[:removed]).to be_empty
      expect(diff_remove_all[:removed]).to eq({ base.manifests.first.path => [duped] })

      expect(diff_remove_one[:added]).to be_empty
      expect(diff_remove_all[:added]).to be_empty
    end
  end

  describe "#changes" do
    let(:dummy_update_to_3) { update_me_3 }

    it "can identify the simple case when a package is updated" do
      base = test_snapshot_with_deps([update_me_1, keep_me])
      target = test_snapshot_with_deps([update_me_2, keep_me])

      diff = Snapshots::Diff.new(base, target)
      changes = diff.changes

      expect(changes).
        to eq([Snapshots::Update.new(
            manifest_path: "package.json",
            name: "update_me",
            old_version: "1.0.0",
            new_version: "2.0.0",
            scope: "runtime",
            new_scope: "runtime"
            )])
    end

    it "can add changes from a ds-api Twirp response" do
      base = test_snapshot_with_deps([update_me_1, keep_me])
      target = test_snapshot_with_deps([update_me_2, keep_me])

      diff = Snapshots::Diff.new(base, target, decompose_updates: true)
      diff.combine_with_twirp_diff(example_twirp_diff)
      changes = diff.changes

      expect(changes).to match_array([
          Snapshots::Addition.new(
            manifest_path: "package.json",
            name: "update_me",
            version: "2.0.0",
            scope: "runtime",
          ),
          Snapshots::Removal.new(
            manifest_path: "package.json",
            name: "update_me",
            version: "1.0.0",
            scope: "runtime",
          ),
          # NOTES about some weirdness here.
          # 1. We must add `= ` to snapshot versions to allow version range matching.
          #    Maybe that should be done elsewhere, including possibly in ds-api.
          # 2. The `scope` field is a little odd.
          #    * It's not in the snapshot response yet (probably should be).
          #    * In this service, it ultimately must be something that can be converted via `to_sym` to one of:
          #       `:runtime`, `:development`, `:unknown` (see snapshot_diff_model.rb:337, the `twirp_scope` method)
          Snapshots::Addition.new(
            manifest_path: "package-lock.json",
            name: "jquery",
            purl: "pkg:npm/jquery@2.0.0",
            version: "= 2.0.0",
            scope: "runtime",
            snapshot_metadata: example_snapshot_metadata,
          ),
          Snapshots::Removal.new(
            manifest_path: "package-lock.json",
            name: "jquery",
            version: "1.0.0",
            purl: "pkg:npm/jquery@1.0.0",
            scope: "runtime",
            snapshot_metadata: example_snapshot_metadata,
          )
        ])
    end

    it "doesn't get confused when a removal and addition have different scopes" do
      base = test_snapshot_with_deps([
          test_dep(name: "not_update", version: "1.0.0", scope: "testing"),
          keep_me])
      target = test_snapshot_with_deps([
          test_dep(name: "not_update", version: "2.0.0", scope: "runtime"),
          keep_me])

      diff = Snapshots::Diff.new(base, target)
      changes = diff.changes

      expect(changes).to match_array([
          Snapshots::Removal.new(
            manifest_path: "package.json",
            name: "not_update",
            version: "1.0.0",
            scope: "testing"
          ),
          Snapshots::Addition.new(
            manifest_path: "package.json",
            name: "not_update",
            version: "2.0.0",
            scope: "runtime"
          )])
    end

    it "leaves plain additions and removals alone" do
      base = test_snapshot_with_deps([remove_me, keep_me])
      target = test_snapshot_with_deps([add_me, keep_me])

      diff = Snapshots::Diff.new(base, target)
      changes = diff.changes

      expect(changes).to match_array([
          Snapshots::Removal.from_dependency(
            manifest_path: "package.json",
            dependency: remove_me
          ),
          Snapshots::Addition.from_dependency(
            manifest_path: "package.json",
            dependency: add_me
          )
        ])
    end

    context "multiple version updates" do
      let (:snapshot_update_1) { Snapshots::Update.new(
        manifest_path: "package.json",
        name: "update_me",
        old_version: "1.0.0",
        new_version: "1.0.1",
        scope: "runtime",
        new_scope: "runtime"
      )
      }

      let (:snapshot_update_2) { Snapshots::Update.new(
        manifest_path: "package.json",
        name: "update_me",
        old_version: "2.0.0",
        new_version: "2.0.1",
        scope: "runtime",
        new_scope: "runtime"
      )
      }

      it "handles multiple package updates properly (with dummy addition)" do
        base = test_snapshot_with_deps([update_me_1, update_me_2])
        target = test_snapshot_with_deps([update_me_1_0_1, update_me_2_0_1, dummy_update_to_3])

        diff = Snapshots::Diff.new(base, target)
        changes = diff.changes

        expect(changes).to match_array([
            snapshot_update_1,
            snapshot_update_2,
            Snapshots::Addition.new(
              manifest_path: "package.json",
              name: "update_me",
              version: dummy_update_to_3.version,
              scope: dummy_update_to_3.scope
            )
          ])
      end

      it "handles multiple package updates properly (with dummy removal)" do
        base = test_snapshot_with_deps([update_me_1, update_me_2, dummy_update_to_3])
        target = test_snapshot_with_deps([update_me_1_0_1, update_me_2_0_1])

        diff = Snapshots::Diff.new(base, target)
        changes = diff.changes

        expect(changes).to match_array([
            snapshot_update_1,
            snapshot_update_2,
            Snapshots::Removal.new(
              manifest_path: "package.json",
              name: "update_me",
              version: dummy_update_to_3.version,
              scope: dummy_update_to_3.scope
            )
          ])
      end
    end

    context "decomposed updates" do
      let (:decomposed_update_removal_1) { Snapshots::Removal.new(
        manifest_path: "package.json",
        name: "update_me",
        version: "1.0.0",
        scope: "runtime"
      )
      }

      let (:decomposed_update_addition_1) { Snapshots::Addition.new(
        manifest_path: "package.json",
        name: "update_me",
        version: "1.0.1",
        scope: "runtime"
      )
      }

      let (:decomposed_update_addition_2) { Snapshots::Addition.new(
        manifest_path: "package.json",
        name: "update_me",
        version: "2.0.1",
        scope: "runtime"
      )
      }

      let (:decomposed_update_removal_2) { Snapshots::Removal.new(
        manifest_path: "package.json",
        name: "update_me",
        version: "2.0.0",
        scope: "runtime"
      )
      }

      it "returns an update as a removal and addition" do
        base = test_snapshot_with_deps([update_me_1, keep_me])
        target = test_snapshot_with_deps([update_me_2, keep_me])

        diff = Snapshots::Diff.new(base, target, decompose_updates: true)
        changes = diff.changes

        expect(changes).to match_array([
          Snapshots::Removal.new(
            manifest_path: "package.json",
            name: "update_me",
            version: "1.0.0",
            scope: "runtime"
          ),
          Snapshots::Addition.new(
            manifest_path: "package.json",
            name: "update_me",
            version: "2.0.0",
            scope: "runtime"
          )])
      end

      it "leaves plain additions and removals alone" do
        base = test_snapshot_with_deps([remove_me, keep_me])
        target = test_snapshot_with_deps([add_me, keep_me])

        diff = Snapshots::Diff.new(base, target, decompose_updates: true)
        changes = diff.changes

        expect(changes).to match_array([
            Snapshots::Removal.from_dependency(
              manifest_path: "package.json",
              dependency: remove_me
            ),
            Snapshots::Addition.from_dependency(
              manifest_path: "package.json",
              dependency: add_me
            )
          ])
      end

      it "handles multiple package updates properly (with dummy addition)" do
        base = test_snapshot_with_deps([update_me_1, update_me_2])
        target = test_snapshot_with_deps([update_me_1_0_1, update_me_2_0_1, dummy_update_to_3])

        diff = Snapshots::Diff.new(base, target, decompose_updates: true)
        changes = diff.changes

        expect(changes).to match_array([
            decomposed_update_addition_1,
            decomposed_update_removal_1,
            decomposed_update_addition_2,
            decomposed_update_removal_2,
            Snapshots::Addition.new(
              manifest_path: "package.json",
              name: "update_me",
              version: dummy_update_to_3.version,
              scope: dummy_update_to_3.scope
            )
          ])
      end

      it "handles multiple package updates properly (with dummy removal)" do
        base = test_snapshot_with_deps([update_me_1, update_me_2, dummy_update_to_3])
        target = test_snapshot_with_deps([update_me_1_0_1, update_me_2_0_1])

        diff = Snapshots::Diff.new(base, target, decompose_updates: true)
        changes = diff.changes

        expect(changes).to match_array([
          decomposed_update_addition_1,
          decomposed_update_removal_1,
          decomposed_update_addition_2,
          decomposed_update_removal_2,
            Snapshots::Removal.new(
              manifest_path: "package.json",
              name: "update_me",
              version: dummy_update_to_3.version,
              scope: dummy_update_to_3.scope
            )
          ])
      end
    end
  end

  describe "#apply" do
    let (:addition_base) { test_snapshot_with_deps([test_dep(name: "keep_me")]) }
    let (:addition_target) { test_snapshot_with_deps([test_dep(name: "keep_me"), test_dep(name: "add_me")]) }

    let (:removal_base) { test_snapshot_with_deps([test_dep(name: "remove_me"), test_dep(name: "keep_me")]) }
    let (:removal_target) { test_snapshot_with_deps([test_dep(name: "keep_me")]) }

    let (:update_base) { test_snapshot_with_deps([test_dep(name: "update_me", version: "1.0.0")]) }
    let (:update_target) { test_snapshot_with_deps([test_dep(name: "update_me", version: "2.0.0")]) }

    def expect_manifest_match(result, target)
      expect(result.manifests.count).to eq(target.manifests.count)
      expect(result.manifests.map(&:path)).to match_array(result.manifests.map(&:path))

      # manifests can get re-ordered by apply, so put them in order by path
      result_manifests = result.manifests.sort_by { |m| m.path }
      target_manifests = target.manifests.sort_by { |m| m.path }
      0.upto(result_manifests.count - 1) do |i|
        expect(result_manifests[i].dependencies).to match_array(target_manifests[i].dependencies)
      end
    end


    it "can apply an addition" do
      diff = Snapshots::Diff.new(addition_base, addition_target)
      result = diff.apply(addition_base)
      expect_manifest_match(result, addition_target)
    end

    it "can apply a removal" do
      diff = Snapshots::Diff.new(removal_base, removal_target)
      result = diff.apply(removal_base)
      expect_manifest_match(result, removal_target)
    end

    it "can apply an update" do
      diff = Snapshots::Diff.new(update_base, update_target)
      result = diff.apply(update_base)
      expect_manifest_match(result, update_target)
    end

    it "adds an entire manifest when necessary" do
      base = empty_manifest_snapshot
      target = Snapshots::Snapshot.new(
        metadata: Snapshots::Metadata.new(
          push_id: "123",
          sha: "baddead",
          ref: "main"
          ),
        github_repository_id: "abcdef123",
        manifests: [
          Snapshots::Manifest.new(
            path: "Gemfile",
            oid: "deed",
            dependencies: [test_dep(name: "one"), test_dep(name: "two")]
            )
        ],
        source: :spec
        )

      diff = Snapshots::Diff.new(base, target)
      result = diff.apply(base)
      expect_manifest_match(result, target)
    end

    it "deletes a manifest when necessary" do
      base = Snapshots::Snapshot.new(
        metadata: Snapshots::Metadata.new(
          push_id: "123",
          sha: "baddead",
          ref: "main"
        ),
        github_repository_id: "abcdef123",
        manifests: [
          Snapshots::Manifest.new(
            path: "Gemfile",
            oid: "deed",
            dependencies: [test_dep(name: "one"), test_dep(name: "two")]
          )
        ],
        source: :spec
      )
      target = no_manifest_snapshot

      diff = Snapshots::Diff.new(base, target)
      result = diff.apply(base)
      expect_manifest_match(result, target)
    end

    it "can reliably replicate a target given a base" do
      property_of {
        [SnapshotGenerators::Snapshot.generate, SnapshotGenerators::Snapshot.generate]
      }.check { |(base, target)|
        diff = Snapshots::Diff.new(base, target)
        result = diff.apply(base)

        # match the results one by one
        expect_manifest_match(result, target)
      }
    end

    context "decomposed updates" do
      it "can apply an update as a removal and addition" do
        diff = Snapshots::Diff.new(update_base, update_target, decompose_updates: true)
        result = diff.apply(update_base)
        expect_manifest_match(result, update_target)
      end

      it "can apply plain removals and additions" do
        addition_diff = Snapshots::Diff.new(addition_base, addition_target, decompose_updates: true)
        addition_result = addition_diff.apply(addition_base)

        removal_diff = Snapshots::Diff.new(removal_base, removal_target, decompose_updates: true)
        removal_result = removal_diff.apply(removal_base)

        expect_manifest_match(addition_result, addition_target)
        expect_manifest_match(removal_result, removal_target)
      end
    end
  end

  describe "#to_model" do
    let(:base) { Snapshots::Snapshot.new(
      metadata: Snapshots::Metadata.new(
        push_id: "1234",
        sha: "378a18ae098da719db960260a5d942667ad22984",
        ref: "main"
      ),
      github_repository_id: 1,
      manifests: [
        Snapshots::Manifest.new(
          path: "Gemfile",
          oid: "999",
          dependencies: [
            test_dep(name: "mongrel", version: "1.3.0"), # remove this
            test_dep(name: "daemons", version: "1.0.1") # update this to 1.0.3
          ]
        ),
        Snapshots::Manifest.new( # remove this manifest
          path: "src/Gemfile",
          oid: "808080",
          dependencies: [
            test_dep(name: "gemA", version: "1.1.0"),
            test_dep(name: "gemB", version: "1.2.0")
          ]
        )
      ],
      source: :spec
      )
    }

    let (:target) { Snapshots::Snapshot.new(
      metadata: Snapshots::Metadata.new(
        push_id: "1235",
        sha:  "c18e6fa46ab9caef2710bdc2711157276c57b5f1",
        ref: "main"
      ),
      github_repository_id: 1,
      manifests: [
        Snapshots::Manifest.new(
          path: "Gemfile",
          oid: "111",
          dependencies: [
            test_dep(name: "daemons", version: "1.0.3") # update this to 1.0.3
          ]
        ),
        Snapshots::Manifest.new(
          path: "src/requirements.txt",
          oid: "81282",
          dependencies: [
            test_dep(name: "pandas", version: "1.0.3")
          ]
        )
      ],
      source: :spec
      )
    }

    it "returns something comparable to the original mock response" do
      diff = Snapshots::Diff.new(base, target)
      model = diff.to_model
      expect(model.github_repository_id).to eq(1)
      expect(model.base_sha).to eq(base.metadata.sha)
      expect(model.target_sha).to eq(target.metadata.sha)
      expected_changed_manifests = [
        Snapshots::ManifestDiffModel.new(
          package_manager: :rubygems,
          file_path: "Gemfile",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "daemons",
              target_version: "1.0.3",
              change_type: :updated,
              base_version: "1.0.1",
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "mongrel",
              base_version: "1.3.0",
              change_type: :removed,
              scope: :runtime,
            )
          ]
        ),
        Snapshots::ManifestDiffModel.new(
          package_manager: :python,
          file_path: "src/requirements.txt",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "pandas",
              target_version: "1.0.3",
              change_type: :added,
              scope: :runtime,
            )
          ]
        ),
        Snapshots::ManifestDiffModel.new(
          package_manager: :rubygems,
          file_path: "src/Gemfile",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "gemA",
              base_version: "1.1.0",
              change_type: :removed,
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "gemB",
              base_version: "1.2.0",
              change_type: :removed,
              scope: :runtime,
            )
          ]
        )
      ]

      expect(model.changed_manifests.count).to eql expected_changed_manifests.count
      model.changed_manifests.each_with_index do |manifest, index|
        expected_manifest = expected_changed_manifests[index]
        expect(manifest.file_path).to eql expected_manifest.file_path
        expect(manifest.dependencies.count).to eql expected_manifest.dependencies.count

        manifest.dependencies.each_with_index do |dependency, d_index|
          expected_dependency = expected_manifest.dependencies[d_index]
          expect(dependency.name).to eql expected_dependency.name
        end
      end
    end

    context "decomposed updates" do
      it "returns something comparable to the original mock response" do
        diff = Snapshots::Diff.new(base, target, decompose_updates: true)
        model = diff.to_model
        expect(model.github_repository_id).to eq(1)
        expect(model.base_sha).to eq(base.metadata.sha)
        expect(model.target_sha).to eq(target.metadata.sha)
        expected_changed_manifests = [
          Snapshots::ManifestDiffModel.new(
            package_manager: :rubygems,
            file_path: "Gemfile",
            dependencies: [
              Snapshots::DependencyDiffModel.new(
                name: "daemons",
                base_version: "1.0.1",
                change_type: :removed,
                scope: :runtime,
              ),
              Snapshots::DependencyDiffModel.new(
                name: "daemons",
                target_version: "1.0.3",
                change_type: :added,
                scope: :runtime,
              ),
              Snapshots::DependencyDiffModel.new(
                name: "mongrel",
                base_version: "1.3.0",
                change_type: :removed,
                scope: :runtime,
              )
            ]
          ),
          Snapshots::ManifestDiffModel.new(
            package_manager: :python,
            file_path: "src/requirements.txt",
            dependencies: [
              Snapshots::DependencyDiffModel.new(
                name: "pandas",
                target_version: "1.0.3",
                change_type: :added,
                scope: :runtime,
              )
            ]
          ),
          Snapshots::ManifestDiffModel.new(
            package_manager: :rubygems,
            file_path: "src/Gemfile",
            dependencies: [
              Snapshots::DependencyDiffModel.new(
                name: "gemA",
                base_version: "1.1.0",
                change_type: :removed,
                scope: :runtime,
              ),
              Snapshots::DependencyDiffModel.new(
                name: "gemB",
                base_version: "1.2.0",
                change_type: :removed,
                scope: :runtime,
              )
            ]
          )
        ]

        expect(model.changed_manifests.count).to eql expected_changed_manifests.count
        model.changed_manifests.each_with_index do |manifest, index|
          expected_manifest = expected_changed_manifests[index]
          expect(manifest.file_path).to eql expected_manifest.file_path
          expect(manifest.dependencies.count).to eql expected_manifest.dependencies.count

          manifest.dependencies.each_with_index do |dependency, d_index|
            expected_dependency = expected_manifest.dependencies[d_index]
            expect(dependency.name).to eql expected_dependency.name
          end
        end
      end
    end
  end
end
