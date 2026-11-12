require "rails_helper"
require "db_helpers"

describe Snapshots::SnapshotDiffModel do
  describe "initialization" do
    it "dependency initialization works as expected" do
      removed_dependency = Snapshots::DependencyDiffModel.new(
        name: "mongrel",
        base_version: "1.3.0",
        change_type: :removed,
        scope: :runtime,
      )
      expect(removed_dependency.name).to eq("mongrel")
      expect(removed_dependency.base_version).to eq("1.3.0")
      expect(removed_dependency.change_type).to eq(:removed)

      updated_dependency = Snapshots::DependencyDiffModel.new(
        name: "daemons",
        target_version: "1.0.3",
        change_type: :updated,
        base_version: "1.0.1",
        scope: :runtime,
      )

      expect(updated_dependency.target_version).to eq("1.0.3")
      expect(updated_dependency.change_type).to eq(:updated)

      added_dependency = Snapshots::DependencyDiffModel.new(
        name: "pandas",
        target_version: "1.0.3",
        change_type: :added,
        scope: :runtime,
      )

      expect(added_dependency.target_version).to eq("1.0.3")
      expect(added_dependency.change_type).to eq(:added)
    end

    it "manifest initialization works as expected" do
      dependency_to_contain = Snapshots::DependencyDiffModel.new(
        name: "pandas",
        target_version: "1.0.3",
        change_type: :added,
        scope: :runtime,
      )

      manifest = Snapshots::ManifestDiffModel.new(
        package_manager: :pip,
        file_path: "src/requirements.txt",
        dependencies: [dependency_to_contain]
      )

      expect(manifest.package_manager).to eq(:pip)
      expect(manifest.file_path).to eq("src/requirements.txt")
      expect(manifest.dependencies[0]).to eq(dependency_to_contain)
    end

    it "snapshot diff initialization works as expected" do
      manifest_to_contain = Snapshots::ManifestDiffModel.new(
        package_manager: :pip,
        file_path: "src/requirements.txt",
        dependencies: []
      )

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: [manifest_to_contain]
      )

      expect(snapshot_diff.github_repository_id).to eq(4567)
      expect(snapshot_diff.base_sha).to eq("abcdef")
      expect(snapshot_diff.target_sha).to eq("123456")
      expect(snapshot_diff.changed_manifests[0]).to eq(manifest_to_contain)
    end
  end

  describe "conversion to twirp" do
    let(:expected_changed_manifests) {
      [
        Snapshots::ManifestDiffModel.new(
          package_manager: :rubygems,
          file_path: "Gemfile",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "daemons",
              target_version: "1.0.3",
              change_type: :updated,
              base_version: "1.0.1",
              ecosystem: "rubygems",
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "mongrel",
              base_version: "1.3.0",
              change_type: :removed,
              ecosystem: "rubygems",
              scope: :development,
            )
          ]
        ),
        Snapshots::ManifestDiffModel.new(
          package_manager: :pip,
          file_path: "src/requirements.txt",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "pandas",
              target_version: "1.0.3",
              change_type: :added,
              ecosystem: "pip",
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "beautifulsoup4",
              target_version: ">= 2.0.0",
              change_type: :added,
              ecosystem: "pip",
              scope: :runtime,
            ),
          ]
        )
      ]
    }
    let(:snapshot_diff) {
      Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )
    }

    let(:twirp_response) { snapshot_diff.to_twirp }

    let(:updated_dependency) { twirp_response.changed_manifests[0].dependencies[0] }
    let(:removed_dependency) { twirp_response.changed_manifests[0].dependencies[1] }
    let(:added_dependency) { twirp_response.changed_manifests[1].dependencies[1] }

    it "all up conversion at snapshot diff level works as expected" do
      expect(twirp_response.repository_id).to eq(4567)
      expect(twirp_response.base_sha).to eq("abcdef")
      expect(twirp_response.target_sha).to eq("123456")
      expect(twirp_response.changed_manifests.count).to eq(2)

      first_manifest = twirp_response.changed_manifests[0]
      expect(first_manifest.type).to eq(:PACKAGE_MANAGER_RUBYGEMS)
      expect(first_manifest.file_path).to eq("Gemfile")
      expect(first_manifest.dependencies.count).to eq(2)

      expect(updated_dependency.name).to eq("daemons")
      expect(updated_dependency.target_version).to eq("1.0.3")
      expect(updated_dependency.change_type).to eq(:DEPENDENCY_CHANGE_TYPE_UPDATED)
      expect(updated_dependency.base_version).to eq("1.0.1")
      expect(updated_dependency.scope).to eq(:SCOPE_RUNTIME)

      expect(removed_dependency.name).to eq("mongrel")
      expect(removed_dependency.change_type).to eq(:DEPENDENCY_CHANGE_TYPE_REMOVED)
      expect(removed_dependency.base_version).to eq("1.3.0")
      expect(removed_dependency.scope).to eq(:SCOPE_DEVELOPMENT)

      expect(added_dependency.name).to eq("pandas")
      expect(added_dependency.change_type).to eq(:DEPENDENCY_CHANGE_TYPE_ADDED)
      expect(added_dependency.target_version).to eq("1.0.3")
    end

    it "generates dependency purls as expected" do
      expect(updated_dependency.base_purl).to eq("pkg:gem/daemons@1.0.1")
      expect(updated_dependency.target_purl).to eq("pkg:gem/daemons@1.0.3")

      expect(removed_dependency.base_purl).to eq("pkg:gem/mongrel@1.3.0")
      expect(removed_dependency.target_purl).to eq("pkg:gem/mongrel")

      expect(added_dependency.base_purl).to eq("pkg:pypi/pandas")
      expect(added_dependency.target_purl).to eq("pkg:pypi/pandas@1.0.3")

      # for now, we want requirement strings to not generate purls
      beautiful_soup = twirp_response.changed_manifests[1].dependencies[0]
      expect(beautiful_soup.base_purl).to eq("pkg:pypi/beautifulsoup4")
      expect(beautiful_soup.target_purl).to eq("pkg:pypi/beautifulsoup4")
    end
  end

  describe "loads vulnerabilities" do
    it "loads vulnerabilities if applicable entries exist in db" do
      rails_vvr_1 = factory.given_vulnerable_version_range({
        github_id: 100,
        package_name: "rails",
        package_manager: :rubygems,
        version_range: ">= 5.0.0, < 5.1.0"
      })
      rails_vvr_2 = factory.given_vulnerable_version_range({
        github_id: 110,
        package_name: "rails",
        package_manager: :rubygems,
        version_range: ">= 5.0.1, < 5.0.4"
      })
      lodash_vvr = factory.given_vulnerable_version_range({
        github_id: 120,
        package_name: "lodash",
        package_manager: :npm,
        version_range: ">= 3.0.0, < 4.0.0"
      })
      brodash_vvr = factory.given_vulnerable_version_range({
        github_id: 130,
        package_name: "brodash",
        package_manager: :npm,
        version_range: ">= 3.0.0, < 4.0.0"
      })
      # This vuln shouldn't be included because brodash can't float into the 3.5.X + range with ~
      brodash_vvr_2 = factory.given_vulnerable_version_range({
        github_id: 140,
        package_name: "brodash",
        package_manager: :npm,
        version_range: ">= 3.5.0, < 4.0.0"
      })

      expected_changed_manifests = [
        Snapshots::ManifestDiffModel.new(
          package_manager: :rubygems,
          file_path: "Gemfile",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "rails",
              target_version: " = 5.0.3",
              change_type: :updated,
              base_version: "= 4.0.1",
              scope: :runtime,
            )
          ]
        ),
        Snapshots::ManifestDiffModel.new(
          package_manager: :npm,
          file_path: "src/package-lock.json",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "lodash",
              target_version: "= 3.5.0",
              change_type: :added,
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "brodash",
              target_version: "~ 3.2.0",
              change_type: :added,
              scope: :runtime,
            )
          ]
        ),
        Snapshots::ManifestDiffModel.new(
          package_manager: :npm,
          file_path: "src/package-lock.json",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "brodash",
              target_version: "^ 3.2.0",
              change_type: :added,
              scope: :runtime,
            )
          ]
        )
      ]

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )

      snapshot_diff.load_vulnerabilities
      rails_dep = snapshot_diff.changed_manifests[0].dependencies[0]
      lodash_dep = snapshot_diff.changed_manifests[1].dependencies[0]
      brodash_dep = snapshot_diff.changed_manifests[1].dependencies[1]
      brodash_dep_with_loose_wildcard = snapshot_diff.changed_manifests[2].dependencies[0]

      expect(rails_dep.github_vulnerability_range_ids.count).to eq(2)
      expect(rails_dep.github_vulnerability_range_ids).to match_array([rails_vvr_1.github_id, rails_vvr_2.github_id])

      expect(lodash_dep.github_vulnerability_range_ids.count).to eq(1)
      expect(lodash_dep.github_vulnerability_range_ids).to match_array([lodash_vvr.github_id])

      # these two brodash deps are testing out overap and mutual exclusion scenarios for vuln lookup
      # brodash_dep is a tilda, which matches PATCH version changes -- should be exclusive to the second vuln, which occurs > 3.2.X
      # brodash_dep_with_loose_wildcard is a carat, which matches MINOR version changes, which can overlap the second vuln, since it's 3.X.X.
      expect(brodash_dep.github_vulnerability_range_ids.count).to eq(1)
      expect(brodash_dep.github_vulnerability_range_ids).to match_array([brodash_vvr.github_id])

      expect(brodash_dep_with_loose_wildcard.github_vulnerability_range_ids.count).to eq(1)
      expect(brodash_dep_with_loose_wildcard.github_vulnerability_range_ids).to match_array([brodash_vvr.github_id])
    end

    it "loads no vulns if no vulns exist" do
      expected_changed_manifests = [
        Snapshots::ManifestDiffModel.new(
          package_manager: :rubygems,
          file_path: "Gemfile",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "rails",
              target_version: "5.0.3",
              change_type: :updated,
              base_version: "4.0.1",
              scope: :runtime,
            )
          ]
        ),
      ]

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )

      snapshot_diff.load_vulnerabilities
      rails_dep = snapshot_diff.changed_manifests[0].dependencies[0]

      expect(rails_dep.github_vulnerability_range_ids.count).to eq(0)
    end

    it "loads vulnerabilities case insensitive should return" do
      lodash_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 120,
                                                            package_name: "microsoft.identityModel.clients.activedirectory",
                                                            package_manager: :nuget,
                                                            version_range: ">= 3.0.0, < 4.0.0"
                                                          })

      expected_changed_manifests = [
        Snapshots::ManifestDiffModel.new(
          package_manager: :nuget,
          file_path: "src/provider.csproj",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "Microsoft.IdentityModel.Clients.ActiveDirectory",
              target_version: "= 3.5.0",
              change_type: :added,
              scope: :runtime,
            )
          ]
        )
      ]

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )

      snapshot_diff.load_vulnerabilities
      lodash_dep = snapshot_diff.changed_manifests[0].dependencies[0]

      expect(lodash_dep.github_vulnerability_range_ids.count).to eq(1)
      expect(lodash_dep.github_vulnerability_range_ids).to match_array([lodash_vvr.github_id])
    end

    it "doesn't blow up if no manifests are in diff" do
      expected_changed_manifests = []

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )

      snapshot_diff.load_vulnerabilities
    end

    it "loads yarn vulnerabilities successfully" do
      lodash_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 120,
                                                            package_name: "lodash",
                                                            package_manager: :npm,
                                                            version_range: ">= 3.0.0, < 4.0.0"
                                                          })
      sprocket_vvr = factory.given_vulnerable_version_range({
                                                             github_id: 140,
                                                             package_name: "sprocket",
                                                             package_manager: :npm,
                                                             version_range: ">= 3.0.0, < 4.8.0"
                                                           })

      expected_changed_manifests = [
        Snapshots::ManifestDiffModel.new(
          package_manager: :npm,
          file_path: "src/package-lock.json",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "lodash",
              target_version: "= 3.5.0",
              change_type: :added,
              scope: :runtime,
            )
          ]
        ),
        Snapshots::ManifestDiffModel.new(
          package_manager: :npm,
          file_path: "src/yarn.lock",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "sprocket",
              target_version: "= 4.5.0",
              change_type: :added,
              scope: :runtime,
            )
          ]
        )
      ]

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 2345,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )

      snapshot_diff.load_vulnerabilities
      lodash_dep = snapshot_diff.changed_manifests[0].dependencies[0]
      sprocket_dep = snapshot_diff.changed_manifests[1].dependencies[0]

      expect(lodash_dep.github_vulnerability_range_ids.count).to eq(1)
      expect(lodash_dep.github_vulnerability_range_ids).to match_array([lodash_vvr.github_id])

      expect(sprocket_dep.github_vulnerability_range_ids.count).to eq(1)
      expect(sprocket_dep.github_vulnerability_range_ids).to match_array([sprocket_vvr.github_id])
    end

    it "loads vulns on removed deps if decomposing updates" do
      httparty_vvr = factory.given_vulnerable_version_range({
                                                            github_id: 120,
                                                            package_name: "httparty",
                                                            package_manager: :rubygems,
                                                            version_range: ">= 3.0.0, < 4.0.0"
                                                          })

      expected_changed_manifests = [
        Snapshots::ManifestDiffModel.new(
          package_manager: :rubygems,
          file_path: "Gemfile.lock",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "httparty",
              base_version: "= 3.5.0",
              change_type: :removed,
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "httparty",
              target_version: "= 4.1.0",
              change_type: :added,
              scope: :runtime,
            ),
          ]
        )
      ]

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )

      snapshot_diff.load_vulnerabilities(decompose_updates: true)
      httparty_remove = snapshot_diff.changed_manifests[0].dependencies[0]
      httparty_add = snapshot_diff.changed_manifests[0].dependencies[1]

      expect(httparty_remove.github_vulnerability_range_ids.count).to eq(1)
      expect(httparty_remove.github_vulnerability_range_ids).to match_array([httparty_vvr.github_id])

      expect(httparty_add.github_vulnerability_range_ids).to be_empty
    end

    it "loads metadata from package release" do
      rails_oldest = factory.given_package("rails", "4.0.1").release
      rails_expected = factory.given_package("rails", "5.0.3")
                               .update_package(repository_id: 1234)
                               .update_package_repository(nwo: "some/repo").release

      rails_expected.license = "MIT"
      rails_expected.github_repository_id = 1234
      rails_expected.published_at = DateTime.new(2015, 10, 10)
      rails_expected.unpublished_at = DateTime.new(2017, 10, 10)
      rails_expected.save
      rails_newer  = factory.given_package("rails", "5.0.4").release

      lodash_expected = factory.given_package("lodash", "3.5.0", :npm).release
      lodash_expected.license = "Apache"
      lodash_expected.save
      brodash_expected = factory.given_package("brodash", "4.5.0", :npm).release
      brodash_expected.license = "GPL"
      brodash_expected.save

      expected_changed_manifests = [
        Snapshots::ManifestDiffModel.new(
          package_manager: :rubygems,
          file_path: "Gemfile",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "rails",
              target_version: "= 5.0.3",
              change_type: :added,
              base_version: "= 4.0.1",
              scope: :runtime,
            )
          ]
        ),
        Snapshots::ManifestDiffModel.new(
          package_manager: :npm,
          file_path: "src/package-lock.json",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "lodash",
              target_version: "= 3.5.0",
              change_type: :updated,
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "brodash",
              target_version: "= 4.5.0",
              change_type: :removed,
              scope: :runtime,
            )
          ]
        )
      ]

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )

      snapshot_diff.load_metadata

      rails_dep = snapshot_diff.changed_manifests[0].dependencies[0]
      expect(rails_dep.license).to eq("MIT")
      expect(rails_dep.repo_nwo).to eq("some/repo")
      expect(rails_dep.github_repository_id).to eq(1234)
      expect(rails_dep.published_at).to eq(DateTime.new(2015, 10, 10))
      expect(rails_dep.unpublished_at).to eq(DateTime.new(2017, 10, 10))

      lodash_dep = snapshot_diff.changed_manifests[1].dependencies[0]
      expect(lodash_dep.license).to eq("Apache")

      brodash_dep = snapshot_diff.changed_manifests[1].dependencies[1]
      expect(brodash_dep.license).to eq("GPL")
    end

    it "loads fallback metadata from package" do
      httparty = factory.given_package("httparty", "1.0.0", :rubygems)
      httparty.update_package({ repository_id: 9876 })
              .update_package_repository({ nwo: "stuff/httparty" })

      rake = factory.given_package("rake", "1.0.0", :rubygems)
      rake.update_package({ repository_id: 9877 })
          .update_package_repository({ nwo: "stuff/rake" })

      pry = factory.given_package("pry", "1.0.0", :rubygems)
      pry.update_package({ repository_id: 9878 })
         .update_package_repository({ nwo: "stuff/pry" })


      expected_changed_manifests = [
        Snapshots::ManifestDiffModel.new(
          package_manager: :rubygems,
          file_path: "Gemfile",
          dependencies: [
            Snapshots::DependencyDiffModel.new(
              name: "httparty",
              target_version: ">= 2.3.0", # ranges can't use package releases
              change_type: :added,
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "rake",
              target_version: "1.3.0", # version we have no package release for
              change_type: :added,
              scope: :runtime,
            ),
            Snapshots::DependencyDiffModel.new(
              name: "pry",
              target_version: "1.0.0", # version we a release for but no repo data attached to it
              change_type: :added,
              scope: :runtime,
            ),
          ]
        ),
      ]

      snapshot_diff = Snapshots::SnapshotDiffModel.new(
        github_repository_id: 4567,
        base_sha: "abcdef",
        target_sha: "123456",
        changed_manifests: expected_changed_manifests
      )

      snapshot_diff.load_metadata

      httparty_diff = snapshot_diff.changed_manifests[0].dependencies[0]
      expect(httparty_diff.repo_nwo).to eq("stuff/httparty")
      expect(httparty_diff.github_repository_id).to eq(9876)
      expect(httparty_diff.license).to be_nil
      expect(httparty_diff.published_at).to be_nil
      expect(httparty_diff.unpublished_at).to be_nil

      rake_diff = snapshot_diff.changed_manifests[0].dependencies[1]
      expect(rake_diff.repo_nwo).to eq("stuff/rake")
      expect(rake_diff.github_repository_id).to eq(9877)
      expect(rake_diff.license).to be_nil
      expect(rake_diff.published_at).to be_nil
      expect(rake_diff.unpublished_at).to be_nil

      pry_diff = snapshot_diff.changed_manifests[0].dependencies[2]
      pry_release = get_package_release("pry", "1.0.0")

      # no repo data attached to pry release
      expect(pry_release.repository_nwo).to be_nil
      expect(pry_release.repository_id).to be_nil

      expect(pry_diff.repo_nwo).to eq("stuff/pry")
      expect(pry_diff.github_repository_id).to eq(9878)
      expect(pry_diff.license).to be_nil
      expect(pry_diff.published_at).to be_nil
      expect(pry_diff.unpublished_at).to be_nil
    end
  end
end
