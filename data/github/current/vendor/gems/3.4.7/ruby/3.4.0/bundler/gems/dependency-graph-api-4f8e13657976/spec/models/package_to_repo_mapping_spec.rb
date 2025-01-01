require "rails_helper"

describe "PackageToRepoMapping" do
  context "when a package claims a repo ID and has a corresponding manifest" do
    let(:rails) { get_package("rails") }

    it "assigns a high certainty score" do
      factory.given_package("rails", "1.2.0")
        .update_repository_mapping(github_repository_id: 100)

      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 100
      })

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 100
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MATCHING_MANIFEST
    end

    it "references the latest package release with repo metadata" do
      # Earliest
      factory.given_package("rails", "1.1.0")

      # Early
      factory.given_package("rails", "1.2.0")
          .update_repository_mapping(github_repository_id: 100)
      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 100
      })

      # More recent, repo metadata updated
      factory.given_package("rails", "1.3.0")
          .update_repository_mapping(github_repository_id: 200)
      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 200
      })

      # Latest, but lacks repo metadata
      factory.given_package("rails", "1.4.0")

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 200
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MATCHING_MANIFEST
    end

    it "doesn't get confused when a manifest from an unclaimed repo matches" do
      factory.given_package("rails", "1.2.0")
        .update_repository_mapping(github_repository_id: 300)
      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 300
      })
      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 100
      })

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 300
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MATCHING_MANIFEST
    end

    it "requires exact name matches" do
      factory.given_package("Rails", "1.2.0")
        .update_repository_mapping(github_repository_id: 300)
      repository = Repository.where({
        github_repository_id: 300
      }).first_or_create!

      Manifest.create!({
        repository:      repository,
        manifest_type:   :gemspec,
        name:            "rails",
        package_manager: :rubygems,
        latest_git_ref:  "abc",
        last_pushed_at:  Time.now,
      })

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 300
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end

    it "falls back to package name" do
      factory.given_package("rails", "1.2.0")
        .update_package(label: nil)
        .update_repository_mapping(github_repository_id: 300)
      repository = Repository.where({
        github_repository_id: 300
      }).first_or_create!

      Manifest.create!({
        repository:      repository,
        manifest_type:   :gemspec,
        name:            "rails",
        package_manager: :rubygems,
        latest_git_ref:  "abc",
        last_pushed_at:  Time.now,
      })

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 300
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MATCHING_MANIFEST
    end

    it "doesn't override greater repo ID certainties" do
      factory.given_package("rails", "1.2.0")
        .update_repository_mapping(github_repository_id: 100)

      repo = Repository.create!(github_repository_id: 1000)
      PackageToRepoMapping::OverrideMatcher.record_match!(rails, PackageToRepoMapping::RepoMatch.from_repo(repo))

      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 100
      })

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 1000
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::OVERRIDE
    end
  end

  context "when a package claims a repo ID but has no corresponding manifest" do
    let(:rails) { get_package("rails") }
    let(:rails_fork) { get_package("rails-fork") }

    before do
      factory do
        rails = given_package("rails", "1.2.0")
          .update_repository_mapping(github_repository_id: 100)
          .package

        given_corresponding_manifest_for_package(rails, {
          github_repository_id: 100
        })
      end
    end

    it "infers a repo when it finds a matching manifest" do
      # Someone forked a package and didn't update metadata
      factory.given_package("rails-fork", "1.2.0")
        .update_repository_mapping(github_repository_id: 100)
      factory.given_corresponding_manifest_for_package(rails_fork, {
        github_repository_id: 500
      })

      PackageToRepoMapping::Matcher.process(rails_fork)

      expect(rails_fork.github_repository_id).to eq 500
      expect(rails_fork.repository_id_certainty).to eq PackageToRepoMapping::Certainty::INFERRED_SINGLE_MATCH
    end

    it "requires an exact name match" do
      factory.given_package("Rails-Fork", "1.2.0")
        .update_repository_mapping(github_repository_id: 100)
      factory.given_corresponding_manifest_for_package(rails_fork, {
        name: "rails-fork",
        github_repository_id: 500
      })

      PackageToRepoMapping::Matcher.process(rails_fork)

      expect(rails_fork.github_repository_id).to eq 100
      expect(rails_fork.repository_id_certainty).to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end

    it "doesn't include non-root manifest" do
      factory.given_package("rails-fork", "1.2.0")
        .update_repository_mapping(github_repository_id: 100)
      factory.given_corresponding_manifest_for_package(rails_fork, {
        github_repository_id: 600,
        path: "vendor"
      })
      factory.given_corresponding_manifest_for_package(rails_fork, {
        github_repository_id: 500
      })

      PackageToRepoMapping::Matcher.process(rails_fork)

      expect(rails_fork.github_repository_id).to eq 500
    end

    it "handles the absence of a matching manifest" do
      # Someone forked a package locally, didn't update metadata, and it
      # doesn't exist on GitHub.
      factory.given_package("rails-fork", "1.2.0")
        .update_repository_mapping(github_repository_id: 100)

      PackageToRepoMapping::Matcher.process(rails_fork)

      expect(rails_fork.github_repository_id).to eq 100
      expect(rails_fork.repository_id_certainty).to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end
  end

  context "when a package doesn't claim a repo ID" do
    let(:rails) { get_package("rails") }

    it "doesn't find a repo" do
      factory.given_package("rails", "1.2.0")

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to be_nil
    end

    it "infers a repo when it finds a matching manifest" do
      # Package owner doesn't maintain repo metadata
      factory.given_package("rails", "1.2.0")

      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 100
      })

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 100
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::INFERRED_SINGLE_MATCH
    end

    it "doesn't infer a single repo when the package manager is maven" do
      # Package owner doesn't maintain repo metadata Package is maven,
      # and since the weak_matcher only looks for manifests in the
      # root directory, we get false positives on this matcher if we
      # turn it on for maven
      guava = factory.given_package("com.google.guava:guava-gwt", "1.0.0", :maven).package
      factory.given_corresponding_manifest_for_package(guava, {
        github_repository_id: 100
      })

      PackageToRepoMapping::Matcher.process(guava)

      expect(guava.github_repository_id).to eq 100
      expect(guava.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MAVEN_INFERRED_NAMESPACE_MULTIPLE_MATCHES
    end

    it "resets repo if a no-longer valid match exists" do
      factory.given_package("rails", "1.2.0")
        .update_package({
          github_repository_id: 1000,
          repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
        })

      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 100
      })
      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 100
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::INFERRED_SINGLE_MATCH
    end

    it "resets repo if a no-longer valid match exists 2" do
      factory.given_package("rails", "1.2.0")
      .update_repository_mapping(github_repository_id: 100)

      manifest = factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 100
      })
      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 100
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MATCHING_MANIFEST

      # When the manifest is deleted we expect to go back to unverified
      manifest.destroy!
      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 100
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end
  end

  describe "inferring a repo when package name at root doesn't match but the namespace does" do
    let(:guava) { factory.given_package("com.google.guava:guava-gwt", "1.0.0", :maven).package }

    it "still finds the correct repo" do
      StarCount.create(github_repository_id: 420, star_count: 1)
      factory.given_corresponding_manifest_for_package(guava, {
        name: "com.google.guava:guava-parent",
        github_repository_id: 420,
        path: ""
      })

      StarCount.create(github_repository_id: 2000, star_count: 2000)
      factory.given_corresponding_manifest_for_package(guava, {
        name: "com.google.guava:guava-parent",
        github_repository_id: 2000,
        path: ""
      })
      factory.given_corresponding_manifest_for_package(guava, {
        name: "com.google.guava:guava-gwt",
        github_repository_id: 2000,
        path: "guava"
      })

      PackageToRepoMapping::Matcher.process(guava)

      expect(guava.github_repository_id).to eq 2000
      expect(guava.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MAVEN_INFERRED_NAMESPACE_MULTIPLE_MATCHES
    end

    it "does not match the repo, if only vendoring a piece of it" do
      StarCount.create(github_repository_id: 2000, star_count: 2000)
      factory.given_corresponding_manifest_for_package(guava, {
        name: "com.google.guava:guava-parent",
        github_repository_id: 2000,
        path: "vendor"
      })
      factory.given_corresponding_manifest_for_package(guava, {
        name: "com.google.guava:guava-gwt",
        github_repository_id: 2000,
        path: "vendor:guava"
      })

      PackageToRepoMapping::Matcher.process(guava)
      expect(guava.github_repository_id).to be_nil
    end

    it "it should not match if not maven" do
      guava_rb = factory.given_package("com.google.guava:guava-gwt", "1.0.0").package
      StarCount.create(github_repository_id: 2000, star_count: 2000)
      factory.given_corresponding_manifest_for_package(guava_rb, {
        name: "com.google.guava:guava-parent",
        github_repository_id: 2000,
        path: ""
      })
      factory.given_corresponding_manifest_for_package(guava_rb, {
        name: "com.google.guava:guava-gwt",
        github_repository_id: 2000,
        path: "guava"
      })

      PackageToRepoMapping::Matcher.process(guava_rb)
      expect(guava_rb.github_repository_id).to be_nil
    end
  end

  describe "inferring the manifest for nuget repos" do
    let(:nuget_pkg) { factory.given_package("SomeNugetPackage", "1.0.0", :nuget).package }

    it "matches manifests in whitelisted directories" do
      StarCount.create(github_repository_id: 2000, star_count: 2000)
      factory.given_corresponding_manifest_for_package(nuget_pkg, {
        name: "SomeNugetPackage",
        github_repository_id: 2000,
        path: "src/foo/bar"
      })
      PackageToRepoMapping::Matcher.process(nuget_pkg)
      expect(nuget_pkg.github_repository_id).to eq 2000
      expect(nuget_pkg.repository_id_certainty).to eq PackageToRepoMapping::Certainty::NUGET_INFERRED_NAMESPACE_MULTIPLE_MATCHES

      StarCount.create(github_repository_id: 3000, star_count: 3000)
      factory.given_corresponding_manifest_for_package(nuget_pkg, {
        name: "SomeNugetPackage",
        github_repository_id: 3000,
        path: "nuget/foo/bar"
      })
      PackageToRepoMapping::Matcher.process(nuget_pkg)
      expect(nuget_pkg.github_repository_id).to eq 3000
      expect(nuget_pkg.repository_id_certainty).to eq PackageToRepoMapping::Certainty::NUGET_INFERRED_NAMESPACE_MULTIPLE_MATCHES
    end

    it "doesn't match manifests outside of the whitelisted directories" do
      StarCount.create(github_repository_id: 1000, star_count: 2000)
      factory.given_corresponding_manifest_for_package(nuget_pkg, {
        name: "SomeNugetPackage",
        github_repository_id: 1000,
        path: "foo/bar"
      })
      PackageToRepoMapping::Matcher.process(nuget_pkg)
      expect(nuget_pkg.github_repository_id).to be_nil
    end
  end

  describe ".update" do
    let(:rails) { get_package("rails") }
    let(:httparty) { get_package("httparty") }

    it "incremmentally maps new packages" do
      factory.given_package("rails", "1.2.0")
        .update_package_release(repository_id: 100)
      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 100
      })

      PackageToRepoMapping::Matcher.process(rails)

      expect(rails.github_repository_id).to eq 100
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MATCHING_MANIFEST

      factory.given_package("rails", "1.3.0")
        .update_package_release(repository_id: 200)
      factory.given_corresponding_manifest_for_package(rails, {
        github_repository_id: 200
      })

      factory.given_package("httparty", "0.0.1")
        .update_package_release(repository_id: 300)
      factory.given_corresponding_manifest_for_package(httparty, {
        github_repository_id: 300
      })

      PackageToRepoMapping::Matcher.process(rails)
      PackageToRepoMapping::Matcher.process(httparty)

      expect(rails.github_repository_id).to eq 200
      expect(rails.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MATCHING_MANIFEST
      expect(httparty.github_repository_id).to eq 300
      expect(httparty.repository_id_certainty).to eq PackageToRepoMapping::Certainty::MATCHING_MANIFEST
    end
  end

  describe "authoritative ecosystems" do
    it "rerunning matchers for a github.com-prefixed Go module does not overwrite repo match" do
      nwo = "chzyer/readline"
      repo = Repository.create!(github_repository_id: 124, public: true, nwo: nwo)
      mod = factory.given_package("github.com/chzyer/readline", "0.0.0", :go, repository_id: repo.github_repository_id,
                                  repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH).package

      PackageToRepoMapping::Matcher.process(mod)
      expect(mod.github_repository_id).to eq 124
      expect(mod.repository_id_certainty).to eq PackageToRepoMapping::Certainty::POSITIVE_MATCH
    end

    it "fails to locate a repo for a non-existent Go module" do
      mod = factory.given_package("no.such.domain", "0.0.0", :go).package
      PackageToRepoMapping::Matcher.process(mod)
      expect(mod.github_repository_id).to eq nil
    end

    it "rerunning matchers for an Actions package does not overwrite mapping" do
      nwo = "actions/checkout"
      repo = Repository.create!(github_repository_id: 125, public: true, nwo: nwo)
      package = factory.given_package("actions/checkout", "1.0.0", :actions, repository_id: repo.github_repository_id,
                                      repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH).package

      PackageToRepoMapping::Matcher.process(package)
      expect(package.github_repository_id).to eq 125
      expect(package.repository_id_certainty).to eq PackageToRepoMapping::Certainty::POSITIVE_MATCH
    end

    it "fails to locate a repo for non-existent Actions package" do
      package = factory.given_package("blahblah/blah", "4.0.4", :actions).package
      PackageToRepoMapping::Matcher.process(package)
      expect(package.github_repository_id).to eq nil
    end
  end
end
