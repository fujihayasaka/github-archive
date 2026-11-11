require "rails_helper"

describe Manifest do
  it "has dependency specs" do
    manifest = Manifest.create!({
      package_manager: :rubygems,
      manifest_type:   :gemfile,
      filename:        "Gemfile",
      path:            "",
      latest_git_ref:  "77dab21",
      last_pushed_at:  Time.now,
    })

    spec = manifest.dependencies.create!({
      package_name:          "rails",
      requirements:          "~> 4.2.0",
      scope:                 :runtime,
      last_seen_at_revision: 0,
    })

    expect(manifest.dependencies).to eq [spec]
  end

  describe ".in_subdirectories" do
    it "matches manifests in subdirectories" do
      manifest = factory.given_manifest(
        github_repo_id: 1,
        filename:       "zookeeper.gemspec",
        path:           "src/foo/bar",
      ).manifest

      expect(described_class.in_subdirectories("src", "foo")).to include(manifest)
      expect(described_class.in_subdirectories("foo/", "src/")).to include(manifest)
      expect(described_class.in_subdirectories("foo")).not_to include(manifest)
    end

    it "matches manifests in a subdirectory" do
      manifest = factory.given_manifest(
        github_repo_id: 1,
        filename:       "Xamarin.Forms.nuspec",
        path:           ".nuspec",
      ).manifest

      expect(described_class.in_subdirectories(".nuspec")).to include(manifest)
      expect(described_class.in_subdirectories(".nuspec/")).to include(manifest)
      expect(described_class.in_subdirectories("foo")).not_to include(manifest)
    end
  end

  describe ".in_same_repository_as" do
    let(:defaults) do
      {
        package_manager: :rubygems,
        manifest_type:   :gemfile,
        filename:        "Gemfile",
        latest_git_ref:  "77dab21",
        last_pushed_at:  Time.now,
      }
    end

    it "includes other manifests in the same repo" do
      repository_1 = Repository.create!({
        github_repository_id: 10
      })
      repository_2 = Repository.create!({
        github_repository_id: 20
      })
      repository_3 = Repository.create!({
        github_repository_id: 30
      })

      manifest_1a = repository_1.manifests.create!(defaults)
      manifest_1b = repository_1.manifests.create!(defaults.merge({
        manifest_type: :gemspec
      }))

      manifest_2a = repository_2.manifests.create!(defaults)
      manifest_2b = repository_2.manifests.create!(defaults.merge({
        manifest_type: :gemspec
      }))

      manifest_3a = repository_3.manifests.create!(defaults)
      manifest_3b = repository_3.manifests.create!(defaults.merge({
        manifest_type: :gemspec
      }))

      expect(described_class.in_same_repository_as([
        manifest_1a,
        manifest_2a
      ])).to eq([manifest_1b, manifest_2b])
    end
  end

  describe ".alphabetized" do
    it "returns manifests in alphabetical order" do
      manifest_1 = factory.given_manifest(
        github_repo_id: 1,
        filename:       "zookeeper.gemspec",
        path:           "",
      ).manifest
      manifest_2 = factory.given_manifest(
        github_repo_id: 2,
        filename:       "Gemfile",
        path:           "",
      ).manifest

      expect(described_class.alphabetized).to eq [
        manifest_2,
        manifest_1,
      ]
    end
  end

  describe ".least_nested_first" do
    it "returns unnested manifests first" do
      manifest_1 = factory.given_manifest(
        github_repo_id: 1,
        filename:       "Gemfile",
        path:           "",
      ).manifest
      manifest_2 = factory.given_manifest(
        github_repo_id: 1,
        filename:       "Gemfile",
        path:           "/",
      ).manifest
      manifest_3 = factory.given_manifest(
        github_repo_id: 2,
        filename:       "abc.gemspec",
        path:           "/lib/subdir",
      ).manifest
      manifest_4 = factory.given_manifest(
        github_repo_id: 2,
        filename:       "def.gemspec",
        path:           "/lib",
      ).manifest

      expect(described_class.least_nested_first).to eq [
        manifest_1,
        manifest_2,
        manifest_4,
        manifest_3,
      ]
    end
  end

  describe ".with_dependencies" do
    it "only includes manifests with dependencies" do
      included = factory
        .given_manifest(github_repo_id: 100, manifest_type: :gemfile)
        .add_dependency("rake", "> 0.0.0")
        .manifest

      excluded = factory
        .given_manifest(github_repo_id: 200, manifest_type: :gemfile)

      expect(described_class.with_dependencies).to eq [included]
    end
  end

  describe ".of_type" do
    it "includes manifests with the given type" do
      included_1 = factory.given_manifest(manifest_type: :gemfile).manifest
      included_2 = factory.given_manifest(manifest_type: :gemfile_lock).manifest
      excluded = factory.given_manifest(manifest_type: :package_json).manifest

      expect(described_class.of_type([
        Types::Manifest[:gemfile],
        Types::Manifest[:gemfile_lock]
      ])).to match_array [included_1, included_2]
    end
  end

  it "allows two manifests in the same path" do
    req = Manifest.create!({
      repository_id: 1,
      package_manager: :pip,
      manifest_type:   :requirements_txt,
      filename:        "requirements.txt",
      path:            "",
      latest_git_ref:  "77dab21",
      last_pushed_at:  Time.now,
    })

    req_test = Manifest.create!({
      repository_id: 1,
      package_manager: :pip,
      manifest_type:   :requirements_txt,
      filename:        "requirements-test.txt",
      path:            "",
      latest_git_ref:  "77dab22",
      last_pushed_at:  Time.now,
    })

    expect(req.filename).to_not eq req_test.filename
  end
end
