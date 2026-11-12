require "rails_helper"

module Ingest
  describe PackageReleaseDependentCountUpdater do
    let(:owner_id) { 12345 }

    describe "#run" do
      context "with Actions ecosystem" do
        it "increments counts for exact version matches (SHA pinning)" do
          # Create an Actions package release with SHA version
          sha_version = "172239021f7ba04fe7327647b213799853a9eb89"
          factory.given_package("actions/checkout", sha_version, Types::PackageManager[:actions])

          # Simulate a manifest dependency with exact SHA version
          dependencies_in_last_revision = []
          dependencies_in_this_revision = [
            build_dependency("actions/checkout", "= #{sha_version}", Types::PackageManager[:actions])
          ]

          updater = PackageReleaseDependentCountUpdater.new(
            github_owner_id: owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision
          )

          expect {
            updater.run
          }.to change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }.by(1)

          count_record = Views::PackageReleaseDependentCount.find_by(github_owner_id: owner_id)
          expect(count_record.count).to eq(1)
        end

        it "increments counts for full semver versions (v3.0.0 style)" do
          # Create an Actions package release with full semver version
          factory.given_package("actions/checkout", "3.0.0", Types::PackageManager[:actions])

          # Simulate a manifest dependency with exact semver version (no wildcards)
          dependencies_in_last_revision = []
          dependencies_in_this_revision = [
            build_dependency("actions/checkout", "= 3.0.0", Types::PackageManager[:actions])
          ]

          updater = PackageReleaseDependentCountUpdater.new(
            github_owner_id: owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision
          )

          expect {
            updater.run
          }.to change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }.by(1)

          count_record = Views::PackageReleaseDependentCount.find_by(github_owner_id: owner_id)
          expect(count_record.count).to eq(1)
        end

        it "increments counts for short tag versions by stripping wildcards (v4 style)" do
          # Package releases use the base version tag (e.g., "4")
          factory.given_package("actions/checkout", "4", Types::PackageManager[:actions])

          # Parser expands short tags to wildcard ranges for vulnerability matching
          # v4 -> = 4.*.* in stored requirements
          dependencies_in_last_revision = []
          dependencies_in_this_revision = [
            build_dependency("actions/checkout", "= 4.*.*", Types::PackageManager[:actions])
          ]

          updater = PackageReleaseDependentCountUpdater.new(
            github_owner_id: owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision
          )

          # Wildcards are stripped when matching to package releases
          expect {
            updater.run
          }.to change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }.by(1)

          count_record = Views::PackageReleaseDependentCount.find_by(github_owner_id: owner_id)
          expect(count_record.count).to eq(1)
        end

        it "increments counts for two-part semver versions by stripping wildcards (v2.1 style)" do
          # Package releases use the base version tag (e.g., "2.1")
          factory.given_package("actions/setup-node", "2.1", Types::PackageManager[:actions])

          # Parser expands two-part tags to wildcard ranges
          # v2.1 -> = 2.1.* in stored requirements
          dependencies_in_last_revision = []
          dependencies_in_this_revision = [
            build_dependency("actions/setup-node", "= 2.1.*", Types::PackageManager[:actions])
          ]

          updater = PackageReleaseDependentCountUpdater.new(
            github_owner_id: owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision
          )

          # Wildcards are stripped when matching to package releases
          expect {
            updater.run
          }.to change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }.by(1)

          count_record = Views::PackageReleaseDependentCount.find_by(github_owner_id: owner_id)
          expect(count_record.count).to eq(1)
        end

        it "decrements counts when dependencies are removed" do
          # Set up an existing package with a count
          package_release = factory.given_package("actions/checkout", "3.0.0", Types::PackageManager[:actions]).release
          Views::PackageReleaseDependentCount.create!(
            github_owner_id: owner_id,
            package_release_id: package_release.id,
            count: 5
          )

          # Simulate removing the dependency
          dependencies_in_last_revision = [
            build_dependency("actions/checkout", "= 3.0.0", Types::PackageManager[:actions])
          ]
          dependencies_in_this_revision = []

          updater = PackageReleaseDependentCountUpdater.new(
            github_owner_id: owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision
          )

          expect {
            updater.run
          }.to change { Views::PackageReleaseDependentCount.find_by(github_owner_id: owner_id).count }.from(5).to(4)
        end
      end

      context "with Go ecosystem" do
        it "increments counts by normalizing versions with v-prefix" do
          # Go package releases use v-prefix convention
          factory.given_package("github.com/example/module", "v1.2.3", Types::PackageManager[:go])

          # Go manifest requirements omit the v-prefix
          dependencies_in_last_revision = []
          dependencies_in_this_revision = [
            build_dependency("github.com/example/module", "= 1.2.3", Types::PackageManager[:go])
          ]

          updater = PackageReleaseDependentCountUpdater.new(
            github_owner_id: owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision
          )

          # Version is normalized by adding v-prefix for matching
          expect {
            updater.run
          }.to change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }.by(1)
        end
      end

      context "with other ecosystems" do
        it "increments counts for normal exact version matches" do
          factory.given_package("rails", "7.0.0", Types::PackageManager[:rubygems])

          dependencies_in_last_revision = []
          dependencies_in_this_revision = [
            build_dependency("rails", "= 7.0.0", Types::PackageManager[:rubygems])
          ]

          updater = PackageReleaseDependentCountUpdater.new(
            github_owner_id: owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision
          )

          expect {
            updater.run
          }.to change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }.by(1)
        end

        it "does not increment counts for non-exact version requirements" do
          factory.given_package("rails", "7.0.0", Types::PackageManager[:rubygems])

          # Non-exact requirement (has no exact_version)
          dependencies_in_last_revision = []
          dependencies_in_this_revision = [
            build_dependency("rails", "~> 7.0.0", Types::PackageManager[:rubygems])
          ]

          updater = PackageReleaseDependentCountUpdater.new(
            github_owner_id: owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision
          )

          # Filtered out in to_dependency_set because requirement_set.exact_version is nil
          expect {
            updater.run
          }.to_not change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }
        end
      end
    end

    # Helper method to build a dependency struct that matches what ManifestLoader provides
    def build_dependency(package_name, requirements, package_manager)
      requirement_set = Versioning::RequirementSet.deserialize(requirements, allow_named_versions: true)

      OpenStruct.new(
        package_name: package_name,
        package_manager: package_manager,
        requirement_set: requirement_set
      )
    end
  end
end
