require "rails_helper"

module Views
  describe PackageReleaseDependentCount do
    let(:owner_id) { 98765 }

    before(:each) do
      # Create some fake PackageReleases
      [[1, "package1", "4.2.1"], [1, "package2", "5.2.3"], [1, "package3", "1.0.0"]].each do |manager, name, version|
        package = Package.create(name: name)
        package.releases.create(name: version, package_manager: manager, package_name: name)
      end
    end

    it "rebuilds package release dependent counts" do
      allow(Rails.application.stats).to receive(:distribution)

      repo = factory.given_repository(github_owner_id: owner_id)
      manifest_factory = factory.given_manifest(repository: repo, manifest_type: Types::Manifest[:gemfile_lock])

      manifest_factory.add_dependency("package1", "= 4.2.1", package_manager: 1)
      described_class.rebuild_for(owner_id)

      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count).to eq(1)

      manifest_factory.add_dependency("package2", "= 5.2.3", package_manager: 1)
      manifest_factory.add_dependency("package3", "= 1.0.0", package_manager: 1)
      described_class.rebuild_for(owner_id)

      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count).to eq(3)
    end

    it "rebuilds package release dependent counts for v prefixed packages for select ecosystems" do
      # Package Releases for some ecosystems eg Go have a prefixed v
      factory.given_package("v-prefixed", "v1.2.3", Types::PackageManager[:go])
      factory.given_manifest(manifest_type: Types::Manifest[:go_mod], github_owner_id: owner_id)
      .add_dependency("v-prefixed", "= 1.2.3", package_manager: Types::PackageManager[:go])

      expect {
        described_class.rebuild_for(owner_id)
      }.to change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }.by(1)

      # v prefixed package releases for other ecosystems are not valid and should be ignored
      factory.given_package("sample-gem", "v4.5.6")
      factory.given_manifest(manifest_type: Types::Manifest[:gemfile_lock], github_owner_id: owner_id)
        .add_dependency("sample-gem", "= 4.5.6")

      expect {
        described_class.rebuild_for(owner_id)
      }.not_to change { Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count }
    end

    it "rebuilds counts with only dependents in the latest revision of a manifest" do
      repo1 = factory.given_repository(github_owner_id: owner_id)
      repo2 = factory.given_repository(github_owner_id: owner_id)

      mf1 = factory.given_manifest(repository: repo1, manifest_type: Types::Manifest[:gemfile_lock])
      mf2 = factory.given_manifest(repository: repo2, manifest_type: Types::Manifest[:gemfile_lock])

      mf1.add_dependency("package1", "= 4.2.1", package_manager: 1)
      mf2.add_dependency("package1", "= 4.2.1", package_manager: 1)

      described_class.rebuild_for(owner_id)

      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).first.count).to eq(2)

      # # update manifests to a new revision and only keep 1 package in the latest revision
      mf1.update_manifest(revision: 1)
      mf2.update_manifest(revision: 1)
      dependency = mf1.manifest.dependencies.where(package_name: "package1", package_manager: 1)
      dependency.update(last_seen_at_revision: 1)

      described_class.rebuild_for(owner_id)

      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).first.count).to eq(1)
    end

    it "rebuilds counts even if there are no dependents in the latest revision of a manifest" do
      repo1 = factory.given_repository(github_owner_id: owner_id)
      repo2 = factory.given_repository(github_owner_id: owner_id)

      mf1 = factory.given_manifest(repository: repo1, manifest_type: Types::Manifest[:gemfile_lock])
      mf2 = factory.given_manifest(repository: repo2, manifest_type: Types::Manifest[:gemfile_lock])

      mf1.add_dependency("package1", "= 4.2.1", package_manager: 1)
      mf2.add_dependency("package1", "= 4.2.1", package_manager: 1)

      described_class.rebuild_for(owner_id)

      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).first.count).to eq(2)

      # update manifests to a new revision
      mf1.update_manifest(revision: 1)
      mf2.update_manifest(revision: 1)

      described_class.rebuild_for(owner_id)

      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count).to eq(0)

      mf2.add_dependency("package3", "= 1.0.0", package_manager: 1)
      described_class.rebuild_for(owner_id)

      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count).to eq(1)
    end
  end
end
