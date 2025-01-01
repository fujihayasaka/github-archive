require "rails_helper"

module Ingest
  describe PackageLoader do
    let(:release) {
      Packages::PackageRelease.new(
        package_manager: :rubygems,
        package_name: "some_package_name",
        version: "0.0.1",
        built_at: Time.iso8601("2021-12-15T00:00:11Z"),
        published_at: Time.iso8601("2021-12-15T00:00:22Z"),
        unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
      )
    }

    it "loads the package into the database" do
      expect { PackageLoader.new(release).load }.to change(Package, :count)
    end

    it "instruments package loading" do
      expect {
        PackageLoader.new(release).load
      }.to have_instrumented_time_dist("etl.packages.insert_package_and_release.dist.time",
                                      { package_manager: "rubygems" })
    end

    describe "rust", vcr: { cassette_name: "package-loader-rust" } do
      let(:release) {
        Packages::PackageRelease.new(
          package_manager: :rust,
          package_name: "crab_pot",
          source_url: "https://github.com/elireisman/crab_pot",
          docs_url: "https://docs.rs/crab_pot",
          description: "Unsafe at any speed",
          version: "1.2.3",
          published_at: Time.iso8601("2022-06-30T09:00:00Z"),
          license: "MIT OR Apache-2.0",
        )
      }
      let(:loader) { PackageLoader.new(release) }

      it "creates a local record of a new repository" do
        expect(Repository.find_by(nwo: "elireisman/crab_pot")).to be nil

        expect { loader.load }.to change(Package, :count)

        repo = Repository.find_by(nwo: "elireisman/crab_pot")
        expect(repo).not_to be nil

        pkg = Package.find_by(name: "crab_pot")
        expect(pkg.repository).to eq repo
        expect(pkg.repository_id_certainty).to eq PackageToRepoMapping::Certainty::POSITIVE_MATCH

        # TODO: PackageReleases delegate to parent Package record for repo ID, NWO, and certainty
        # so these are not updated by matcher-based overrides the package loader applies. We should
        # drop these fields from dg_package_releases since they are unused!
        pkg_release = PackageRelease.find_by(package_name: "crab_pot", name: "1.2.3")
        expect(pkg_release.repository_id).to eq repo.github_repository_id
        # UPDATE (8/2023): As part of the OSPO backfill we're bumping PackageReleases
        # and parent Package to POSITIVE_MATCH for all "authoritative" ecosystems
        expect(pkg_release.repository_id_certainty).to eq PackageToRepoMapping::Certainty::POSITIVE_MATCH
      end
    end

    describe "go", vcr: { cassette_name: "package-loader-starlark" } do
      let(:release) {
        Packages::PackageRelease.new(
          package_manager: :go,
          package_name: "go.starlark.net",
          source_url: "https://github.com/google/starlark-go",
          version: "0.0.0",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
      }
      let(:loader) { PackageLoader.new(release) }

      it "creates a local record of a new repository" do
        expect(Repository.find_by(nwo: "google/starlark-go")).to be nil

        loader.load

        repo = Repository.find_by(nwo: "google/starlark-go")
        expect(repo).not_to be nil
        expect(Package.find_by(name: "go.starlark.net").repository).to eq repo
      end
    end

    describe "named versions" do
      let(:action_release) { Packages::PackageRelease.new(
        package_manager: :actions,
        package_name: "actions/checkout",
        source_url: "https://github.com/actions/checkout",
        version: "main",
        built_at: Time.iso8601("2021-12-15T00:00:11Z"),
        published_at: Time.iso8601("2021-12-15T00:00:22Z"),
        unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
      )
      }

      before do
        Repository.create!(
          github_repository_id: 700,
          github_owner_id: 1234,
          nwo: "actions/checkout",
          public: true,
        )
        PackageLoader.new(action_release).load
      end

      it "successfully stores release with named version" do
        expect(Package.count).to eq 1

        checkout_release = PackageRelease.find_by(package_name: "actions/checkout")
        expect(checkout_release.name).to eq "main"
      end

      it "does not store encoded version in release" do
        expect(PackageRelease.find_by(package_name: "actions/checkout").encoded).to be_nil
      end
    end

    describe "non-authoritative registries" do
      it "if the registry has a source_url to a public GitHub repository, we should map the package to it with Certainty::UNVERIFIED" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "rails/rails",
          public: true,
        )
        release = Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          source_url: "https://github.com/rails/rails",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("rails")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::UNVERIFIED)
      end

      it "heuristics should take precedence over source_url" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "rails/rails",
          public: true,
        )
        Repository.create!(
          github_repository_id: 2,
          github_owner_id: 2,
          nwo: "github/rails",
          public: true,
        )
        factory.given_manifest(
          github_repo_id: 2,
          package_manager: Types::PackageManager[:rubygems],
          manifest_type:  :gemspec,
          filename:       "gemspec",
          path:           "",
          name: "rails"
        )
        release = Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          source_url: "https://github.com/rails/rails",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("rails")
        expect(package.repository_id).to eq(2)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::INFERRED_SINGLE_MATCH)
      end

      it "if there's a source_url, release should map to the repo with Certainty::UNVERIFIED" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "rails/rails",
          public: true,
        )
        release = Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          source_url: "https://github.com/rails/rails",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        release = PackageRelease.find_by_package_name("rails")
        expect(release.repository_id).to eq(1)
        expect(release.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::UNVERIFIED)
      end

      it "if there's no source_url, we should run heuristics" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "rails/rails",
          public: true,
        )
        factory.given_manifest(
          github_repo_id: 1,
          package_manager: Types::PackageManager[:rubygems],
          manifest_type:  :gemspec,
          filename:       "gemspec",
          path:           "",
          name: "rails"
        )
        release = Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          source_url: nil,
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("rails")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::INFERRED_SINGLE_MATCH)
      end

      it "if there's a source_url to a non-GitHub repository, it should behave as if there's no source_url" do
        release = Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          source_url: "https://gitlab.com/rails/rails",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("rails")
        expect(package.repository_id).to eq(nil)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::NULL)
      end

      it "manual overrides should take precedence" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "rails/rails",
          public: true,
        )
        Repository.create!(
          github_repository_id: 2,
          github_owner_id: 2,
          nwo: "some/repo",
          public: true,
        )
        rails = factory.given_package("rails", "1.2.0")
              .update_package(repository_id: 1, repository_id_certainty: PackageToRepoMapping::Certainty::OVERRIDE, package_manager: Types::PackageManager[:rubygems])
              .package
        factory.given_manifest(
          github_repo_id: 1,
          package_manager: Types::PackageManager[:rubygems],
          manifest_type:  :gemspec,
          filename:       "gemspec",
          path:           "",
          name: "rails"
        )
        release = Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          source_url: "https://github.com/some/repo",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("rails")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::OVERRIDE)
      end
    end

    # Tests for package-to-repository mapping for "authoritative" registries.
    # These tests assert the behaviour specified in https://github.com/github/dependency-graph/issues/1314.
    describe "authoritative registries" do
      it "if the registry has a source_url to a GitHub repository, then we should map the package to it" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "actions/checkout",
          public: true,
        )
        release = Packages::PackageRelease.new(
          package_manager: :actions,
          package_name: "actions/checkout",
          source_url: "https://github.com/actions/checkout",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("actions/checkout")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      it "if the registry has no source_url, then we should fall back on heuristics to map the package" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "hello/rust",
          public: true,
        )
        factory.given_manifest(
          github_repo_id: 1,
          package_manager: Types::PackageManager[:rust],
          manifest_type:  :cargo_toml,
          filename:       "Cargo.toml",
          path:           "",
          name: "hello/rust"
        )
        release = Packages::PackageRelease.new(
          package_manager: :rust,
          package_name: "hello/rust",
          source_url: nil,
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("hello/rust")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::INFERRED_SINGLE_MATCH)
      end

      it "if the registry had a source_url in the past but not anymore, then we should fall back on heuristics" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "hello/rust",
          public: true,
        )
        release_1 = Packages::PackageRelease.new(
          package_manager: :rust,
          package_name: "hello/rust",
          source_url: "https://github.com/hello/rust",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release_1).load
        package = Package.find_by_name("hello/rust")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::POSITIVE_MATCH)

        release_2 = Packages::PackageRelease.new(
          package_manager: :rust,
          package_name: "hello/rust",
          source_url: nil,
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release_2).load

        package.reload
        expect(package.repository_id).to eq(nil)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::NULL)
      end

      it "if there was no source_url in the registry in the past but now there's one, it should take precedence over heuristics" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "dodgy-hello/rust",
          public: true,
        )
        Repository.create!(
          github_repository_id: 2,
          github_owner_id: 2,
          nwo: "hello/rust",
          public: true,
        )
        factory.given_manifest(
          github_repo_id: 1,
          package_manager: Types::PackageManager[:rust],
          manifest_type:  :cargo_toml,
          filename:       "Cargo.toml",
          path:           "",
          name: "hello/rust"
        )
        release_1 = Packages::PackageRelease.new(
          package_manager: :rust,
          package_name: "hello/rust",
          source_url: nil,
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release_1).load
        package = Package.find_by_name("hello/rust")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::INFERRED_SINGLE_MATCH)

        release_2 = Packages::PackageRelease.new(
          package_manager: :rust,
          package_name: "hello/rust",
          source_url: "https://github.com/hello/rust",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release_2).load

        package.reload
        expect(package.repository_id).to eq(2)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      it "we should map the package based on the source_url of the last ingested release" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "hello/rust",
          public: true,
        )
        Repository.create!(
          github_repository_id: 2,
          github_owner_id: 2,
          nwo: "world/rust",
          public: true,
        )
        factory.given_manifest(
          github_repo_id: 1,
          package_manager: Types::PackageManager[:rust],
          manifest_type:  :cargo_toml,
          filename:       "Cargo.toml",
          path:           "",
          name: "hello/rust"
        )
        release_1 = Packages::PackageRelease.new(
          package_manager: :rust,
          package_name: "hello/rust",
          source_url: "https://github.com/hello/rust",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release_1).load
        package = Package.find_by_name("hello/rust")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::POSITIVE_MATCH)

        release_2 = Packages::PackageRelease.new(
          package_manager: :rust,
          package_name: "hello/rust",
          source_url: "https://github.com/world/rust",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release_2).load

        package.reload
        expect(package.repository_id).to eq(2)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      it "manual overrides should take precedence over registry" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "actions/checkout",
          public: true,
        )
        Repository.create!(
          github_repository_id: 2,
          github_owner_id: 2,
          nwo: "some/repo",
          public: true,
        )
        checkout = factory.given_package("actions/checkout", "1.2.0")
              .update_package(repository_id: 1, repository_id_certainty: PackageToRepoMapping::Certainty::OVERRIDE, package_manager: Types::PackageManager[:actions])
              .package
        release = Packages::PackageRelease.new(
          package_manager: :actions,
          package_name: "actions/checkout",
          source_url: "https://github.com/some/repo",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("actions/checkout")
        expect(package.repository_id).to eq(1)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::OVERRIDE)
      end

      it "if source_url points to a private GitHub repository, set repository_id = nil with Certainty::POSITIVE_MATCH" do
        Repository.create!(
          github_repository_id: 1,
          github_owner_id: 1,
          nwo: "actions/checkout",
          public: false,
        )
        release = Packages::PackageRelease.new(
          package_manager: :actions,
          package_name: "actions/checkout",
          source_url: "https://github.com/actions/checkout",
          version: "main",
          built_at: Time.iso8601("2021-12-15T00:00:11Z"),
          published_at: Time.iso8601("2021-12-15T00:00:22Z"),
          unpublished_at: Time.iso8601("2021-12-15T00:00:33Z"),
        )
        PackageLoader.new(release).load
        package = Package.find_by_name("actions/checkout")
        expect(package.repository_id).to eq(nil)
        expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end
    end

    describe "overwriting logic" do
      before do
        @package = factory.given_package("rails", "7.0.0")
        @package_id = @package.package.id
      end

      it "does not write exisiting license" do
        @package.update_package_release({ license: "MIT" })

        PackageLoader.new(Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          license: "NEWER MIT",
          version: "7.0.0",
        )).load

        release = PackageRelease.find_by(package_id: @package_id, name: "7.0.0")
        expect(release.license).to eq("MIT")
      end

      it "updates the license if there was previously no saved license" do
        PackageLoader.new(Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          license: "Apache",
          version: "7.0.0",
        )).load

        release = PackageRelease.find_by(package_id: @package_id, name: "7.0.0")
        expect(release.license).to eq("Apache")
      end

      it "only overwrites previously set source_url for none nil new value" do
        factory.given_repository(nwo: "some/repo")
        factory.given_repository(nwo: "some/new-repo")
        @package.update_package_release({ source_url: "https://github.com/some/repo" })

        PackageLoader.new(Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          source_url: nil,
          version: "7.0.0",
        )).load

        release = PackageRelease.find_by(package_id: @package_id, name: "7.0.0")
        expect(release.source_url).to eq("https://github.com/some/repo")

        PackageLoader.new(Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          source_url: "https://github.com/some/new-repo",
          version: "7.0.0",
        )).load

        release.reload
        expect(release.source_url).to eq("https://github.com/some/new-repo")
      end

      it "only overwrites previously set publish dates for none nil new values" do
        package = Package.find(@package_id)
        release = PackageRelease.find_by(package_id: @package_id, name: "7.0.0")

        expect(package.last_published_at).to be nil
        expect(release.published_at).to be nil
        expect(release.unpublished_at).to be nil

        PackageLoader.new(Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          version: "7.0.0",
          published_at: Time.iso8601("2022-04-26T15:06:14Z"),
          unpublished_at: Time.iso8601("2023-04-26T15:06:14Z"),
        )).load

        package.reload
        release.reload

        expect(package.last_published_at).to eq(Time.iso8601("2022-04-26T15:06:14Z"))
        expect(release.published_at).to eq(Time.iso8601("2022-04-26T15:06:14Z"))
        expect(release.unpublished_at).to eq(Time.iso8601("2023-04-26T15:06:14Z"))

        PackageLoader.new(Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rails",
          version: "7.0.0",
          published_at: nil,
          unpublished_at: nil
        )).load

        package.reload
        release.reload
        expect(package.last_published_at).to eq(Time.iso8601("2022-04-26T15:06:14Z"))
        expect(release.published_at).to eq(Time.iso8601("2022-04-26T15:06:14Z"))
        expect(release.unpublished_at).to eq(Time.iso8601("2023-04-26T15:06:14Z"))
      end

      it "does not overwrite a PackageRelease if the data is the same" do
        expect(Package.find_by(package_manager: Types::PackageManager::RUBYGEMS, name: "rspec")).to be_nil
        expect(PackageRelease.find_by(package_manager: Types::PackageManager::RUBYGEMS, package_name: "rspec", name: "6.0")).to be_nil

        allow(Instrument).to receive(:increment).and_call_original

        package = Packages::PackageRelease.new(
          package_manager: :rubygems,
          package_name: "rspec",
          version: "6.0",
          license: "MIT",
          published_at: Time.iso8601("2022-04-26T15:06:14Z"),
          unpublished_at: Time.iso8601("2023-04-26T15:06:14Z"),
          dependencies: [
            Packages::PackageRelease::Dependency.new(
              package_name: "rspec-core",
              requirements: ">= 3.0",
              scope: Types::Scope::RUNTIME
            )
          ]
        )

        expect {
          PackageLoader.new(package).load
        }.to(make_database_queries(matching: /INSERT.+dg_package_versions/))

        expect(PackageRelease.find_by(package_manager: Types::PackageManager::RUBYGEMS, package_name: "rspec", name: "6.0")).not_to be_nil

        expect(Instrument).to have_received(:increment).with(
          "etl.packages.load.insert.release",
          package_manager: "rubygems",
          create_release: true,

          # If create_release is true, it is not important what these values actually are.
          # They will probably all be "true" but sometimes, if there is a nil value, they could be "false"
          updated_license: true,
          updated_source_url: false,
          updated_unpublished_at: true,
        )

        # Watch the import method to see if it is called
        allow(PackageDependency).to receive(:import).and_call_original

        # If a package with the same data is loaded again, it should not be written to the database
        expect {
          PackageLoader.new(package).load
        }.not_to(make_database_queries(matching: /INSERT.+dg_package_versions/))

        # Ensure we did not try to add more PackageDependencies
        expect(PackageDependency).not_to have_received(:import)

        expect(Instrument).to have_received(:increment).with(
          "etl.packages.load.insert.release",
          package_manager: "rubygems",
          create_release: false,
          updated_license: false,
          updated_source_url: false,
          updated_unpublished_at: false,
        )
      end
    end
  end
end
