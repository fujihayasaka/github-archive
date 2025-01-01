require "rails_helper"

module Ingest
  describe PackageProcessor do
    include ActiveJob::TestHelper

    let(:package_name) { "httparty" }
    let(:processor) { described_class.new }
    let(:release) {
      {
        package_manager: "rubygems",
        package_name: package_name,
        package_version: "0.10.2",
        authors: "jnunemaker",
        published_at: Time.new(2016, 10, 10).to_i,
        source_url: "http://github.com/jnunemaker/httparty",
        dependencies: [{
          package_name: "multi_xml",
          requirements: "= 2.5.0",
          scope: :runtime
        }],
      }
    }
    let(:rust_package_name) { "crab_pot" }
    let(:rust_release) {
      {
        package_manager: "rust",
        package_name: rust_package_name,
        package_version: "1.2.3",
        description: "Generates nerd snipes to aid in the capture of fresh Rustaceans",
        authors: "",
        license: "Apache-2.0",
        published_at: Time.new(2018, 12, 3).to_i,
        source_url: "https://github.com/elireisman/crab_pot",
        docs_url: "https://docs.rs/crab_pot",
        home_url: "https://example.com/projects/crab_pot",
        dependencies: [{
          package_name: "rand",
          requirements: "> 0.1.0, <= 0.8.5",
          scope: :runtime
        },
        {
          package_name: "itoa",
          requirements: "> 1.2.0, <= 2.0.0",
          scope: :development
        }],
      }
    }

    let(:npm_package_release) {
      {
        package_manager: "npm",
        package_name: "jquery",
        package_version: "1.2.3",
        description: "Mostly for people still using IE 6",
        authors: "",
        license: "Apache-2.0",
        published_at: Time.new(2018, 12, 3).to_i,
        source_url: "https://github.com/jquery/jquery",
        dependencies: []
      }
    }

    def run
      perform_enqueued_jobs do
        process
      end
    end

    def process
      run_consumer(processor)
    end

    before(:each) do
      @repo = Repository.create(github_repository_id: 12, nwo: "jnunemaker/httparty")
      @rust_repo = Repository.create(github_repository_id: 24, nwo: "elireisman/crab_pot")
      Repository.create(github_repository_id: 1337, nwo: "jquery/jquery")
      processor.spec_reset
    end

    # Specs pulled from spec/etl/ingest/package_stage_spec.rb

    it "inserts packages" do
      processor.publish(release)

      expect { run }.to change { Package.count }.by(1)

      package = get_package(package_name)

      expect(package.package_manager).to eq Types::PackageManager[:rubygems]
      expect(package.repository_id).to eq 12
      expect(package.repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end

    it "inserts package versions" do
      processor.publish(release)

      expect { run }.to change { PackageRelease.count }.by(1)

      package_v1 = get_package_release(package_name, "0.10.2")

      expect(package_v1.package_name).to eq("httparty")
      expect(package_v1.package_manager).to eq Types::PackageManager[:rubygems]
      expect(package_v1.published_at).to eq Time.new(2016, 10, 10)
      expect(package_v1.unpublished_at).to be_nil
      expect(package_v1.repository_id).to eq 12
      expect(package_v1.repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end

    it "inserts dependencies" do
      processor.publish(release)

      expect { run }.to change { PackageDependency.count }.by(1)

      package_v1 = get_package_release(package_name, "0.10.2")

      expect(package_v1.dependencies.count).to eq 1
      dependency = package_v1.dependencies.first
      expect(dependency.package_name).to eq "multi_xml"
      expect(dependency.package_manager).to eq Types::PackageManager[:rubygems]
      expect(dependency.requirements).to eq "= 2.5.0"
    end

    it "inserts abstract package dependencies" do
      processor.publish(release)

      expect { run }.to change { AbstractPackageDependency.count }.by(1)

      package = get_package(package_name)

      expect(package.abstract_dependencies.count).to eq 1
      abstract_dependency = package.abstract_dependencies.first
      expect(abstract_dependency.package_name).to eq "multi_xml"
      expect(abstract_dependency.package_manager).to eq Types::PackageManager[:rubygems]
    end

    it "dedupes package dependencies and abstract package dependencies" do
      pip_release = {
        package_manager: "pip",
        package_name:    "MySQL__python",
        package_version: "1.0.0",
        published_at:    Time.new(2016, 10, 10).to_i,
        dependencies: [
          {
            package_name: "foo__bar",
            requirements: "= 2.5.0",
            scope:        :runtime,
          },
          {
            package_name: "foo__bar",
            requirements: "= 2.5.0",
            scope:        :runtime,
          },
          {
            package_name: "foo__bar",
            requirements: "= 2.5.0",
            scope:        :runtime,
          },
          {
            package_name: "foo__bar",
            requirements: "= 2.5.0",
            scope:        :runtime,
          }
        ]
      }

      processor.publish(pip_release)

      expect { run }.to change { PackageDependency.count }.by(1)
        .and change { AbstractPackageDependency.count }.by(1)
    end

    it "respects blocklists" do
      Ingest::Blocklist.clear(type: :packages)
      Ingest::Blocklist.add(type: :packages, item: "#{package_name}:rubygems")

      processor.publish(release)

      expect { run }.to change { PackageRelease.count }.by(0)
      Ingest::Blocklist.clear(type: :packages)
    end

    context "when posting a pip package" do
      before(:each) do
        pip_release = {
          package_manager: "pip",
          package_name:    "MySQL__python",
          package_version: "1.0.0",
          published_at:    Time.new(2016, 10, 10).to_i,
          dependencies: [
            {
              package_name: "foo__bar",
              requirements: "= 2.5.0",
              scope:        :runtime,
            }
          ]
        }

        processor.publish(release)
        processor.publish(pip_release)
      end

      it "normalizes the package name" do
        expect { run }.to change { Package.count }.by(2)
        scope = Package.where(name: "mysql-python")
        expect(scope.count).to eq(1)
      end

      it "keeps the package label" do
        expect { run }.to change { Package.count }.by(2)
        scope = Package.where(label: "MySQL__python")
        expect(scope.count).to eq(1)
      end

      it "normalizes the dependencies package names" do
        expect { run }.to change { PackageDependency.count }.by(2)
        scope = PackageDependency.where(package_name: "foo-bar")
        expect(scope.count).to eq(1)

        scope = PackageDependency.where(package_label: "foo__bar")
        expect(scope.count).to eq(1)
      end
    end

    context "when posting a rubygems package" do
      let(:package_name) { "MySQL__rg" }

      it "doesnt normalizes the package name" do
        processor.publish(release)

        expect { run }.to change { Package.count }.by(1)
        scope = Package.where(name: "MySQL__rg")
        expect(scope.count).to eq(1)
      end
    end

    it "overwrites less certain repository ID mappings" do
      processor.publish(release)

      factory do
        given_package("httparty", "0.10.2")
          .update_package({
            repository_id: 6,
            repository_id_certainty: PackageToRepoMapping::Certainty::NULL
          })
          .update_package_release({
            repository_id: 6,
            repository_id_certainty: PackageToRepoMapping::Certainty::NULL
          })
      end

      run

      expect(get_package(package_name).repository_id).to eq 12
      expect(get_package(package_name).repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED

      expect(get_package_release(package_name, "0.10.2").repository_id).to eq 12
      expect(get_package_release(package_name, "0.10.2").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end

    it "overwrites repository ID mappings of equivalent certainty" do
      processor.publish(release)

      factory do
        given_package("httparty", "0.10.2")
          .update_package({
            repository_id: 6,
            repository_id_certainty: PackageToRepoMapping::Certainty::UNVERIFIED
          })
          .update_package_release({
            repository_id: 6,
            repository_id_certainty: PackageToRepoMapping::Certainty::UNVERIFIED
          })
      end

      run

      expect(get_package(package_name).repository_id).to eq 12
      expect(get_package(package_name).repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED

      expect(get_package_release(package_name, "0.10.2").repository_id).to eq 12
      expect(get_package_release(package_name, "0.10.2").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end

    it "does not overwrite repository ID mappings of greater certainty" do
      processor.publish(release)

      factory do
        given_package("httparty", "0.10.2")
          .update_package({
            repository_id: 6,
            repository_id_certainty: PackageToRepoMapping::Certainty::OVERRIDE
          })
          .update_package_release({
            repository_id: 6,
            repository_id_certainty: PackageToRepoMapping::Certainty::OVERRIDE
          })
      end

      run

      expect(get_package(package_name).repository_id).to eq 6
      expect(get_package(package_name).repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::OVERRIDE

      expect(get_package_release(package_name, "0.10.2").repository_id).to eq 6
      expect(get_package_release(package_name, "0.10.2").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::OVERRIDE
    end

    it "maps repositories we don't know about yet", vcr: { cassette_name: "package-processor-find-repositories" } do
      package_release = {
        package_manager: "rubygems",
        package_name:    "something",
        package_version: "1.2.3",
        source_url:      "http://github.com/github/something",
        published_at:    Time.new(2016, 10, 10).to_i,
      }

      processor.publish(package_release)
      run

      repository = Repository.find_by(nwo: "github/something")
      expect(get_package("something").repository).to eq repository
      expect(get_package("something").repository_nwo).to eq "github/something"
      expect(get_package("something").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED

      expect(get_package_release("something", "1.2.3").repository_id).to eq repository.github_repository_id
      expect(get_package_release("something", "1.2.3").repository_nwo).to eq "github/something"
      expect(get_package_release("something", "1.2.3").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end

    it "does not maps repository ids when the repo is private" do
      repo = Repository.create(github_repository_id: 13, nwo: "github/something", public: false)

      package_release = {
        package_manager: "rubygems",
        package_name:    "something",
        package_version: "1.2.3",
        source_url:      "http://github.com/github/something",
        published_at:    Time.new(2016, 10, 10).to_i,
      }

      processor.publish(package_release)
      run

      expect(get_package("something").repository_id).to be_nil
      expect(get_package("something").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED

      expect(get_package_release("something", "1.2.3").repository_id).to be_nil
      expect(get_package_release("something", "1.2.3").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::UNVERIFIED
    end

    it "doesn't map repositories when we have no url" do
      package_release = {
        package_manager: "rubygems",
        package_name:    "something",
        package_version: "1.2.3",
        published_at:    Time.new(2016, 10, 10).to_i,
      }

      processor.publish(package_release)
      run

      expect(get_package("something").repository_id).to be_nil
      expect(get_package("something").repository_nwo).to be_nil
      expect(get_package("something").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::NULL

      expect(get_package_release("something", "1.2.3").repository_id).to be_nil
      expect(get_package_release("something", "1.2.3").repository_nwo).to be_nil
      expect(get_package_release("something", "1.2.3").repository_id_certainty)
        .to eq PackageToRepoMapping::Certainty::NULL
    end

    it "escapes malicious strings" do
      package_release = {
        package_manager: "rubygems",
        package_name:    "; drop table users; ",
        package_version: "0.10.2",
        source_url:      "http://github.com/jnunemaker/httparty",
        published_at:    Time.new(2016, 10, 10).to_i,
        dependencies:    []
      }

      processor.publish(package_release)
      run

      expect(get_package("; drop table users; ")).to be_present
    end

    it "instruments timing" do
      processor.publish(release)
      expect { run }.to have_instrumented_time_dist("etl.packages.load.dist.time", { package_manager: Types::PackageManager[:rubygems] })
    end

    it "instruments invalid requirements" do
      package_release = {
        package_manager: "rubygems",
        package_name:    package_name,
        package_version: "0.10.2",
        source_url:      "http://github.com/jnunemaker/httparty",
        published_at:    Time.new(2016, 10, 10).to_i,
        dependencies:    [
          {
            package_name: "multi_xml",
            requirements: "= 2.5.0 || GARBAGE",
            scope:        :runtime,
          }
        ],
      }

      processor.publish(package_release)

      expect { run }.to have_instrumented_increment("etl.invalid_requirements", {
        context: {
          stage:        :package_ingest,
        }
      })
    end

    it "handles requirements that are too long" do
      package_release = {
        package_manager: "rubygems",
        package_name:    package_name,
        package_version: "0.10.2",
        source_url:      "http://github.com/jnunemaker/httparty",
        published_at:    Time.new(2016, 10, 10).to_i,
        dependencies:    [
          {
            package_name: "multi_xml",
            requirements: "> 1.2.2.#{'A' * 500}",
            scope:        :runtime,
          }
        ],
      }
      processor.publish(package_release)

      dependency = Packages::PackageRelease::Dependency.new(
        package_name: "multi_xml",
        requirements: "> 1.2.2.#{'A' * 500}",
        scope:        :runtime,
      )

      expect { run }.to have_instrumented_increment("etl.invalid_dependency", {
        dependency: dependency,
        context: {
          stage: :package_ingest,
        }
      })
    end

    it "doesn't create packages published_at 1970-01-01" do
      package_release = {
        package_manager: :rubygems,
        package_name:    package_name,
        published_at:    0,
        source_url:      "http://github.com/jnunemaker/httparty",
        package_version:         "0.0.1",
      }
      processor.publish(package_release)
      run

      package_v0 = get_package_release(package_name, "0.0.1")
      expect(package_v0.published_at).to be_nil
    end

    it "enqueues a job to process packages" do
      sidekiq_release = {
        package_manager: :rubygems,
        package_name:    "sidekiq",
        package_version: "6.0.3",
        source_url:      "https://github.com/mperham/sidekiq/",
        published_at:    Time.new(2019, 10, 10).to_i,
        dependencies:    []
      }

      processor.publish(sidekiq_release)
      process
      expect(LoadPackageJob).to have_been_enqueued
    end

    # specialized Rust/Cargo test cases including new (optional)
    # metadata override fields on release events
    it "inserts packages" do
      processor.publish(rust_release)

      expect { run }.to change { Package.count }.by(1)

      package = get_package(rust_package_name)

      expect(package.package_manager).to eq Types::PackageManager[:rust]
      expect(package.repository_id).to eq 24

      expect(package.repository_id_certainty).to eq PackageToRepoMapping::Certainty::POSITIVE_MATCH
    end

    it "inserts package versions" do
      processor.publish(rust_release)

      expect { run }.to change { PackageRelease.count }.by(1)

      package_v1 = get_package_release(rust_package_name, "1.2.3")

      expect(package_v1.package_name).to eq("crab_pot")
      expect(package_v1.package_manager).to eq Types::PackageManager[:rust]
      expect(package_v1.published_at).to eq Time.new(2018, 12, 3)
      expect(package_v1.unpublished_at).to be_nil
      expect(package_v1.license).to eq "Apache-2.0"

      # TODO: PackageReleases delegate to parent Package record for repo ID and certainty
      # so these are not updated by matcher-based overrides the package loader applies. We should
      # drop these fields from dg_package_releases since they are unused!
      expect(package_v1.package.repository_id).to eq 24
      expect(package_v1.package.repository_id_certainty).to eq PackageToRepoMapping::Certainty::POSITIVE_MATCH
    end

    it "inserts dependencies" do
      processor.publish(rust_release)

      expect { run }.to change { PackageDependency.count }.by(2)

      package_v1 = get_package_release(rust_package_name, "1.2.3")

      expect(package_v1.dependencies.count).to eq 2
      dependency = package_v1.dependencies.find { |d| d.package_name == "rand" }
      expect(dependency.package_name).to eq "rand"
      expect(dependency.requirements).to eq "> 0.1.0,<= 0.8.5"
      expect(dependency.scope).to eq Types::Scope[:runtime]
      expect(dependency.package_manager).to eq Types::PackageManager[:rust]
    end

    it "inserts abstract package dependencies" do
      processor.publish(rust_release)

      expect { run }.to change { AbstractPackageDependency.count }.by(2)

      package = get_package(rust_package_name)

      expect(package.abstract_dependencies.count).to eq 2
      abstract_dependency = package.abstract_dependencies.find { |d| d.package_name == "rand" }
      expect(abstract_dependency.package_name).to eq "rand"
      expect(abstract_dependency.package_manager).to eq Types::PackageManager[:rust]
    end
    # END Rust/Cargo specific unit tests

    # Pulled in from spec/etl/kafka_sink/package_sink_spec.rb
    context "consuming and decoding messages" do
      it "handles un-decodeable messages" do
        allow(Hydro::Schemas::Github::Dependencygraph::V0::PackageRelease)
          .to receive(:encode)
            .and_return "INVALID"

        package_release =  {
          package_manager: :rubygems,
          package_name:    package_name,
          package_version: "0.10.2",
          source_url:      "http://github.com/jnunemaker/httparty",
          published_at:    Time.new(2016, 10, 10).to_i,
          dependencies:    [],
        }

        processor.publish(package_release)

        perform_enqueued_jobs do
          expect { process }.to raise_error(Google::Protobuf::ParseError)
        end
      end
    end

    it "skips processing when the package has not changed" do
      package_release = npm_package_release.merge(package_version: "0.0.1")
      package_release_to_skip = package_release.merge(description: "Changed description")

      processor.publish(package_release)
      processor.publish(package_release_to_skip)

      expect { run }.to change { PackageRelease.count }.by(1)
                    .and have_instrumented_increment("package_processor.skip_job", package_manager: "npm")
    end

    it "does not skip processing when the package source_url has changed" do
      new_repo = Repository.create(github_repository_id: 2448, nwo: "neworg/jquery")

      package_release = npm_package_release.merge(package_version: "0.0.2")
      changed_source_url = package_release.merge(source_url: "https://github.com/neworg/jquery")

      processor.publish(package_release)
      processor.publish(changed_source_url)

      expect { run }.to change { PackageRelease.count }.by(1)
      expect(PackageRelease.find_by(package_name: "jquery", name: "0.0.2").repository_id).to eq new_repo.github_repository_id
    end
  end
end
