require "rails_helper"
require "db_helpers"

include ActiveSupport::Testing::TimeHelpers

module Ingest
  describe ManifestLoader do
    include ActiveJob::TestHelper

    def load_manifests(manifests)
      manifests.each do |manifest|
        ManifestLoader.new(manifest).load
      end
    end

    def manifest(attributes = {})
      ::ManifestAdapters.parse(**{
        git_ref: "2c3edv",
        github_repository_id: 600,
        filename: "pom.xml",
        path: "",
        content: file_fixture("pom.xml").read,
        pushed_at: Time.new(2017, 1, 1),
        fork: false,
        visibility_private: false,
      }.merge(attributes))
    end

    let(:a_manifest) {
      ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "2c3ed2",
        github_repository_id: 600,
        github_owner_id: 1234,
        repository_nwo: "github/github",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "Gemfile",
        path: nil,
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          )
        ],
      )
    }

    it "inserts repositories that are not yet present in the database" do
      manifest_2 = manifest(
          github_repository_id: 600,
          github_owner_id: 1234,
          repository_nwo: "github/github",
          visibility_private: false,
        )

      expect {
        load_manifests([a_manifest, manifest_2])
      }.to change { Repository.count }.by(1)

      repo = get_repo(repo_id: 600)
      expect(repo.github_repository_id).to eq 600
      expect(repo.github_owner_id).to eq 1234
      expect(repo.nwo).to eq "github/github"
      expect(repo.public).to eq true

      expect { load_manifests([manifest_2]) }
        .to change { Repository.count }.by(0)
    end

    it "updates info for repositories that are already present in the database" do
      Repository.create!(
        github_repository_id: 600,
        github_owner_id: 1234,
        nwo: "some-owner/some-repo",
        public: true,
      )
      manifest_2 = manifest(
        github_repository_id: 600,
        github_owner_id: 5678,
        repository_nwo: "some-other-owner/some-repo",
        visibility_private: true,
      )
      expect { load_manifests([a_manifest, manifest_2]) }
        .to change { Repository.count }.by(0)

      repo = get_repo(repo_id: 600)
      expect(repo.github_owner_id).to eq 5678
      expect(repo.nwo).to eq "some-other-owner/some-repo"
      expect(repo.public).to eq false
    end

    it "inserts repository's star count if it's not yet present in the database" do
      manifest_2 = manifest(
        github_repository_id: 600,
        repository_stargazer_count: 42,
      )

      expect(StarCount.exists?(github_repository_id: 600)).to eq false

      expect { load_manifests([a_manifest, manifest_2]) }
        .to change { StarCount.count }.by(1)

      expect(StarCount.exists?(github_repository_id: 600)).to eq true
      repo = get_repo(repo_id: 600)
      expect(repo.star_count).to eq 42

      expect { load_manifests([a_manifest, manifest_2]) }
        .to change { StarCount.count }.by(0)
    end

    it "updates star count for repository if it differs from what is present in the database" do
      Repository.create!(
        github_repository_id: 600,
        github_owner_id: 1234,
        nwo: "some-owner/some-repo",
        public: true,
      )
      StarCount.create(github_repository_id: 600, star_count: 1)
      manifest_2 = manifest(
        github_repository_id: 600,
        repository_stargazer_count: 42,
      )
      expect { load_manifests([a_manifest, manifest_2]) }
        .to change { Repository.count }.by(0)

      repo = get_repo(repo_id: 600)
      expect(repo.star_count).to eq 42
    end

    it "inserts abstract repository dependencies" do
      expect { load_manifests([a_manifest]) }
        .to change { AbstractRepositoryDependency.count }.by(1)

      repo       = get_repo(repo_id: 600)
      dependency = repo.abstract_dependencies.first!

      expect(dependency.package_name).to eq "rails"
    end

    it "only inserts abstract repository dependencies that are not yet present in the database" do
      manifest =  ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "2c3ed2",
        github_repository_id: 600,
        github_owner_id: 1234,
        repository_nwo: "github/github",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "Gemfile",
        path: nil,
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "httparty",
            requirements: "~> 0.17.0",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "nokogiri",
            requirements: "= 1.2.3",
            scope: Types::Scope[:runtime],
          ),
        ],
      )

      repo = Repository.create!(github_repository_id: 600,
        github_owner_id: 1234,
        nwo: "github/github",
        public: true,
      )
      repo.abstract_dependencies.create!(
        package_manager: Types::PackageManager::RUBYGEMS.id,
        package_name: "httparty",
      )
      repo.abstract_dependencies.create!(
        package_manager: Types::PackageManager::RUBYGEMS.id,
        package_name: "nokogiri",
      )

      expect(AbstractRepositoryDependency).to receive(:import) do |columns, values, options|
        expect(columns[2]).to eq(:package_name)
        expect(values.length).to eq(1)
        expect(values[0][2]).to eq("rails")
      end
      load_manifests([manifest])
    end

    it "inserts manifests" do
      expect { load_manifests([a_manifest]) }
        .to change { Manifest.count }.by(1)

      manifest = get_manifest(repo_id: 600, ref: "2c3ed2")

      expect(manifest.package_manager).to eq Types::PackageManager[:rubygems]
      expect(manifest.manifest_type).to eq Types::Manifest[:gemfile]
      expect(manifest.last_pushed_at).to eq Time.new(2017, 01, 01)
      expect(manifest.filename).to eq "Gemfile"
      expect(manifest.path).to be_blank
      expect(manifest.name).to be_blank
      expect(manifest.revision).to eq 0
    end

    it "inserts only dependencies that are not malformed" do
      manifest_2 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "2c3ed2",
        github_repository_id: 600,
        github_owner_id: 1234,
        repository_nwo: "github/github",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "Gemfile",
        path: nil,
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
          package_name: "rails",
          requirements: "~> 4.2.0",
          scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "nokogiri",
            requirements: "= 1.2.3",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "malformed-dep",
            requirements: "",
            scope: Types::Scope[:runtime],
            malformed: true,
          ),
        ],
      )

      expect { load_manifests([a_manifest, manifest_2]) }
        .to change { ManifestEntry.count }.by(2)

      dependencies = get_manifest(repo_id: 600, ref: "2c3ed2")
        .entries

      rails = dependencies.with_package_name("rails").first
      nokogiri = dependencies.with_package_name("nokogiri").first

      expect(rails.package_name).to eq "rails"
      expect(rails.requirements).to eq "~> 4.2.0"
      expect(rails.package_manager).to eq Types::PackageManager[:rubygems]
      expect(rails.requirement_set.exact_version).to be_nil

      expect(nokogiri.package_name).to eq "nokogiri"
      expect(nokogiri.requirements).to eq "= 1.2.3"
      expect(nokogiri.package_manager).to eq Types::PackageManager[:rubygems]
      expect(nokogiri.requirement_set.exact_version).to eq "1.2.3"

      expect(dependencies.with_package_name("malformed-dep").first).to be_nil
    end

    it "normalizes pip manifest dependencies" do
      pipfile = manifest(
        filename: "Pipfile",
        content: <<~EOF
          [[source]]
          url = "https://pypi.org/simple"
          verify_ssl = true
          name = "pypi"

          [packages]
          pip_package = "==0.0.2"

          [requires]
          python_version = "3.10"
        EOF
      )
      poetry_lock = manifest(
        filename: "poetry.lock",
        content: <<~EOF
          [[package]]
          name = "poetry-_._-_-..-package"
          version = "1.26.6"

          [requires]
          python_version = "3.10"
        EOF
      )

      pyproject_toml = manifest(
        filename: "pyproject.toml",
        content: <<~EOF
        [source]
        homepage = 'https://pypi.python.org/simple'
        name = 'pypi'
        python = '2.7'

        [dependencies]
        pyproject___dep = '==1.1a1'
        EOF
      )

      expect {
        load_manifests([pipfile, poetry_lock, pyproject_toml])
      }.to change { ManifestEntry.count }.by(3)

      expect(get_manifest_entry "pip-package").to exist
      expect(get_manifest_entry "pip_package").not_to exist

      expect(get_manifest_entry "poetry-package").to exist
      expect(get_manifest_entry "poetry-_._-_-..-package").not_to exist

      expect(get_manifest_entry "pyproject-dep").to exist
      expect(get_manifest_entry "pyproject__dep").not_to exist
    end

    it "updates the pip dependency instead of creating a new one if the change is to a known variation" do
      manifest_1 = manifest(
        filename: "requirements.txt",
        content: "clickhouse-_._-_-..-driver==0.0.2"
      )
      manifest_2 = manifest(
        filename: "requirements.txt",
        content: "clickhouse__driver==0.0.2",
        git_ref: "1234new",
        pushed_at: Time.now,
      )

      expect {
        load_manifests([manifest_1, manifest_2])
      }.to change { ManifestEntry.count }.by(1)

      expect(get_manifest_entry "clickhouse-driver").to exist
      expect(get_manifest_entry "clickhouse-_._-_-..-driver").not_to exist
      expect(get_manifest_entry "clickhous__driver").not_to exist

      expect(get_manifest_entry("clickhouse-driver").first.last_seen_at_revision).to eq 1
    end

    it "ensures raw requirements for dependencies are persisted" do
      expect { load_manifests([a_manifest, manifest]) }
        .to change { ManifestEntry.count }.by(23)

      dependencies = get_manifest(repo_id: 600, ref: "2c3edv")
        .entries
        .joins(manifest_package_version: :manifest_package)
        .order("#{ManifestPackage.table_name}.package_name")

      package_1 = dependencies.first
      package_2 = dependencies.last

      expect(package_1.package_name).to eq "com.datadoghq:java-dogstatsd-client"
      expect(package_1.requirements).to eq "= 2.5"
      expect(package_1.package_manager).to eq Types::PackageManager[:maven]
      expect(package_1.requirement_set.exact_version).to eq "2.5"

      expect(package_2.package_name).to eq "org.slf4j:slf4j-log4j12"
      expect(package_2.requirements).to eq "= 1.7.7"
      expect(package_2.package_manager).to eq Types::PackageManager[:maven]
      expect(package_2.requirement_set.exact_version).to eq "1.7.7"
    end


    it "normalizes manifest paths" do
      manifest_2 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "2c3ed2",
        github_repository_id: 600,
        repository_nwo: "github/github",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "Gemfile",
        path: "/",
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          ),
        ],
      )
      manifest_3 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "2c3ed2",
        github_repository_id: 600,
        repository_nwo: "github/github",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "Gemfile",
        path: "  /  ",
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          ),
        ],
      )
      manifest_4 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "2c3ed2",
        github_repository_id: 600,
        repository_nwo: "github/github",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "Gemfile",
        path: "",
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          ),
        ],
      )

      load_manifests([a_manifest, manifest_2,  manifest_3, manifest_4])

      expect(Manifest.pluck(:path)).to eq [""]
    end

    describe "updating manifests" do
      let(:manifests) {
        [
          ManifestAdapters::Manifest.new(
            package_manager: :rubygems,
            manifest_type: :gemfile,
            git_ref: "2c3ed2",
            github_repository_id: 600,
            github_owner_id: 1234,
            repository_nwo: "github/github",
            repository_stargazer_count: 12,
            fork: false,
            visibility_private: false,
            pushed_at: Time.new(2017, 01, 01),
            filename: "Gemfile",
            path: nil,
            dependent_name: nil,
            malformed: false,
            dependencies: [
              ManifestAdapters::Manifest::Dependency.new(
                package_name: "rails",
                requirements: "~> 4.2.0",
                scope: Types::Scope[:runtime],
              )
            ],
          ),
          ManifestAdapters::Manifest.new(
            package_manager: :rubygems,
            manifest_type: :gemfile,
            dependent_name: "my project",
            git_ref: "2bda675",
            github_repository_id: 600,
            github_owner_id: 1234,
            repository_nwo: "github/github",
            repository_stargazer_count: 12,
            fork: false,
            visibility_private: false,
            pushed_at: Time.new(2017, 02, 01),
            filename: "Gemfile",
            path: nil,
            malformed: false,
            dependencies: [
              ManifestAdapters::Manifest::Dependency.new(
                package_name: "rails",
                requirements: "~> 5.0.0",
                scope: Types::Scope[:runtime],
              ),
              ManifestAdapters::Manifest::Dependency.new(
                package_name: "rspec",
                requirements: "= 2.2.0",
                scope: Types::Scope[:development],
              ),
            ],
          ),
          ManifestAdapters::Manifest.new(
            package_manager: :rubygems,
            manifest_type: :gemfile,
            dependent_name: "my project",
            git_ref: "90a796",
            github_repository_id: 600,
            github_owner_id: 1235,
            repository_nwo: "github/github2",
            repository_stargazer_count: 13,
            fork: false,
            visibility_private: false,
            pushed_at: Time.new(2017, 03, 01),
            filename: "Gemfile",
            path: nil,
            malformed: false,
            dependencies: [
              ManifestAdapters::Manifest::Dependency.new(
                package_name: "rails",
                requirements: "~> 5.0.0",
                scope: Types::Scope[:runtime],
              ),
              ManifestAdapters::Manifest::Dependency.new(
                package_name: "rspec",
                requirements: "= 2.2.1",
                scope: Types::Scope[:development],
              ),
            ],
          )
        ]
      }

      it "updates the manifest with the latter data" do
        load_manifests(manifests)

        repo = get_repo(repo_id: 600)
        manifest = repo.manifests.find_by(filename: "Gemfile")

        expect(manifest.package_manager).to eq Types::PackageManager[:rubygems]
        expect(manifest.manifest_type).to eq Types::Manifest[:gemfile]
        expect(manifest.last_pushed_at).to eq Time.new(2017, 03, 01)
        expect(manifest.latest_git_ref).to eq "90a796"
        expect(manifest.filename).to eq "Gemfile"
        expect(manifest.name).to eq "my project"
        expect(manifest.revision).to eq 2
      end

      it "updates the rails and rspec dependencies" do
        load_manifests(manifests)

        manifest = get_manifest(repo_id: 600, ref: "90a796")

        rails_dependencies = manifest.entries
          .with_package_name("rails")

        expect(rails_dependencies.count).to eq 2

        dependency_1 = rails_dependencies
          .with_requirements("~> 5.0.0")
          .first!

        expect(dependency_1).not_to eq nil
        expect(dependency_1.last_seen_at_revision).to eq 2

        rspec_dependencies = manifest.entries
          .with_package_name("rspec")

        expect(rspec_dependencies.count).to eq 2

        dependency_2 = rspec_dependencies
          .with_requirements("= 2.2.1")
          .first!

        expect(dependency_2).not_to eq nil
        expect(dependency_2.requirement_set.exact_version).to eq "2.2.1"
        expect(dependency_2.last_seen_at_revision).to eq 2
      end

      it "updates the repository" do
        load_manifests(manifests)

        repo = get_repo(repo_id: 600)

        expect(repo.nwo).to eq "github/github2"
        expect(repo.github_owner_id).to eq 1235
        expect(repo.star_count).to eq 13
      end
    end

    describe "multiple manifests of the same type at different paths" do
      it "imports both manifests" do
        manifest_2 = ManifestAdapters::Manifest.new(
          package_manager: :rubygems,
          manifest_type: :gemfile,
          git_ref: "2c3ed2",
          github_repository_id: 600,
          repository_nwo: "github/github",
          repository_stargazer_count: 12,
          fork: false,
          visibility_private: false,
          pushed_at: Time.new(2017, 03, 01),
          filename: "Gemfile",
          path: "lib",
          dependent_name: nil,
          malformed: false,
          dependencies: [
            ManifestAdapters::Manifest::Dependency.new(
              package_name: "rails",
              requirements: "~> 5.0.0",
              scope: Types::Scope[:runtime],
            ),
          ],
        )
        expect {
          load_manifests([a_manifest, manifest_2])
        }.to change { Repository.count }.by(1)
          .and change { Manifest.count }.by(2)

        manifest_1 = get_manifest(repo_id: 600, ref: "2c3ed2", path: "")

        expect(manifest_1.filename).to eq "Gemfile"
        expect(manifest_1.revision).to eq 0

        manifest_2 = get_manifest(repo_id: 600, ref: "2c3ed2", path: "lib")

        expect(manifest_2.filename).to eq "Gemfile"
        expect(manifest_2.revision).to eq 0
      end
    end

    it "handles malicious strings" do
      manifest_2 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemspec,
        git_ref: "ed22ae",
        dependent_name: "; drop table users; ",
        dependent_version: "0.10.2",
        github_repository_id: 500,
        repository_nwo: "github/nwo",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.now,
        filename: "Gemfile",
        path: nil,
        malformed: false,
        dependencies: [],
      )

      load_manifests([a_manifest, manifest_2])

      manifest = get_manifest(repo_id: 500, ref: "ed22ae")

      expect(manifest.name).to eq "; drop table users; "
    end

    it "instruments timing" do
      expect { load_manifests([a_manifest]) }.to have_instrumented_time_dist("etl.manifests.load.dist.time", package_manager: Types::PackageManager[:rubygems])
    end

    it "instruments invalid requirements" do
      manifest_2 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "ed22ae",
        github_repository_id: 500,
        repository_nwo: "github/nwo",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.now,
        filename: "Gemfile",
        path: nil,
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "multi_xml",
            requirements: "= 2.5.0 || GARBAGE",
            scope: Types::Scope[:runtime],
          )
        ],
      )

      expect {
        load_manifests([a_manifest, manifest_2])
      }.to have_instrumented_increment("etl.invalid_requirements", {
        invalid_range: "GARBAGE",
        context: {
          stage:         :manifest_ingest,
        }
      })
    end

    it "throws away requirements that are too long" do
      manifest_2 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "ed22ae",
        github_repository_id: 500,
        repository_nwo: "github/nwo",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.now,
        filename: "Gemfile",
        path: nil,
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "multi_xml",
            requirements: Array.new(100, "= 5.0.0").join(","),
            scope: Types::Scope[:runtime],
          )
        ],
      )

      expect {
        load_manifests([a_manifest, manifest_2])
      }.to_not change {
        ManifestDependency.where(package_name: "multi_xml").count
      }
    end

    it "doesn't import vendored manifests" do

      manifest_1 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "ed22ae",
        github_repository_id: 500,
        repository_nwo: "github/nwo",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.now,
        filename: "Gemfile",
        path: "vendor/gems",
        dependent_name: nil,
        malformed: false,
        dependencies:    [],
      )
      manifest_2 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "ed22ae",
        github_repository_id: 500,
        repository_nwo: "github/nwo",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.now,
        filename: "Gemfile",
        path: "/vendor/gems",
        dependent_name: nil,
        malformed: false,
        dependencies: [],
      )

      expect {
        load_manifests([manifest_1, manifest_2])
      }.to_not change { Manifest.count }
    end

    it "doesn't import manifests with invalid attributes" do

      manifest_1 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "ed22ae",
        github_repository_id: 500,
        repository_nwo: "github/nwo",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.now,
        filename: "Gemfile",
        path: "a" * 500, # path is too long
        dependent_name: nil,
        malformed: false,
        dependencies: [],
      )
      manifest_2 = ManifestAdapters::Manifest.new(
        dependent_name: "a" * 500, # dependent_name is too long
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "ed22ae",
        github_repository_id: 500,
        repository_nwo: "github/nwo",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.now,
        filename: "Gemfile",
        path: "/vendor/gems",
        malformed: false,
        dependencies: [],
      )

      expect {
        load_manifests([manifest_1, manifest_2])
      }.to_not change { Manifest.count }
    end

    it "should not remap authoritatively mapped package" do
      rails = factory.given_package("hello/rust", "1.2.0")
              .update_package(repository_id: 1, repository_id_certainty: 85, package_manager: Types::PackageManager[:rust])
              .package

      manifest = ManifestAdapters::Manifest.new(
        package_manager: :rust,
        manifest_type: :cargo_toml,
        git_ref: "2c3ed2",
        github_repository_id: 2,
        repository_nwo: "world/rust",
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "cargo.oml",
        path: nil,
        dependent_name: "hello/rust",
        repository_stargazer_count: 0,
        malformed: false,
        dependencies: [],
      )

      load_manifests([manifest])

      package = Package.find_by_name("hello/rust")
      expect(package.repository_id).to eq(1)
      expect(package.repository_id_certainty).to eq(PackageToRepoMapping::Certainty::POSITIVE_MATCH)
    end

    it "handles vendored javascript files" do
      manifest_1 = ManifestAdapters::Manifest.new(
        package_manager: :npm,
        manifest_type: :vendored_javascript_dependency,
        git_ref: "2c3ef1",
        github_repository_id: 700,
        repository_nwo: "github/linguist",
        repository_stargazer_count: 0,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "jquery.js",
        path: nil,
        dependent_name: "",
        malformed: false,
        dependencies: [
         ManifestAdapters::Manifest::Dependency.new(
            package_name: "jquery",
            requirements: "= 1.8.1",
            scope: Types::Scope[:runtime],
         )
        ]
      )

      expect { load_manifests([manifest_1]) }.to change { Manifest.count }.by 1
      manifest = get_manifest(repo_id: 700)

      expect(manifest.entries.count).to eq 1
      dependency = manifest.entries.first
      expect(dependency.package_name).to eq "jquery"
      expect(dependency.requirements).to eq "= 1.8.1"
    end

    it "dedupes manifest dependencies" do

      manifest_2 = ManifestAdapters::Manifest.new(
        package_manager: :rubygems,
        manifest_type: :gemfile,
        git_ref: "2c3ed2",
        github_repository_id: 600,
        github_owner_id: 1234,
        repository_nwo: "github/github",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "Gemfile",
        path: nil,
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "rails",
            requirements: "~> 4.2.0",
            scope: Types::Scope[:runtime],
          )
        ],
      )

      expect { load_manifests([a_manifest, manifest_2]) }.to change { ManifestEntry.count }.by 1
    end

    it "dedupes abstract repository dependencies" do

      manifest_2 = ManifestAdapters::Manifest.new(
          package_manager: :rubygems,
          manifest_type: :gemfile,
          git_ref: "2c3ed2",
          github_repository_id: 600,
          github_owner_id: 1234,
          repository_nwo: "github/github",
          repository_stargazer_count: 12,
          fork: false,
          visibility_private: false,
          pushed_at: Time.new(2017, 01, 01),
          filename: "Gemfile",
          path: nil,
          dependent_name: nil,
          malformed: false,
          dependencies: [
            ManifestAdapters::Manifest::Dependency.new(
              package_name: "rails",
              requirements: "~> 4.2.0",
              scope: Types::Scope[:runtime],
            ),
            ManifestAdapters::Manifest::Dependency.new(
              package_name: "rails",
              requirements: "~> 4.2.0",
              scope: Types::Scope[:runtime],
            ),
            ManifestAdapters::Manifest::Dependency.new(
              package_name: "rails",
              requirements: "~> 4.2.0",
              scope: Types::Scope[:runtime],
            ),
            ManifestAdapters::Manifest::Dependency.new(
              package_name: "rails",
              requirements: "~> 4.2.0",
              scope: Types::Scope[:runtime],
            )
          ],
        )

      expect { load_manifests([a_manifest, manifest_2]) }.to change { AbstractRepositoryDependency.count }.by 1
    end

    context "for Dependency Insights users" do
      let(:gemfile_attrs)  {
        {
          package_manager: :rubygems,
          manifest_type: :gemfile,
          git_ref: "2c3ed2",
          github_repository_id: 600,
          github_owner_id: 1234,
          repository_nwo: "github/github",
          repository_stargazer_count: 12,
          fork: false,
          visibility_private: false,
          pushed_at: Time.new(2017, 01, 01),
          filename: "Gemfile",
          path: nil,
          dependent_name: nil,
          malformed: false,
          dependencies: [
            ManifestAdapters::Manifest::Dependency.new(
              package_name: "rails",
              requirements: "= 4.2.0",
              scope: Types::Scope[:runtime],
            ),
            ManifestAdapters::Manifest::Dependency.new(
              package_name: "rubocop",
              requirements: "= 1.0.1",
              scope: Types::Scope[:runtime],
            ),
            ManifestAdapters::Manifest::Dependency.new(
              package_name: "nokogiri",
              requirements: "= 1.1.1",
              scope: Types::Scope[:runtime],
            )
          ]
        }
      }

      let(:gemfile) { ManifestAdapters::Manifest.new(**gemfile_attrs) }

      let(:gemfile_lock) {
        ManifestAdapters::Manifest.new(**gemfile_attrs.merge({
          manifest_type: :gemfile_lock,
          filename: "Gemfile.lock"
        }))
      }

      before do
        # Ensure our GitHub Owner ID has a backfill record so this code will run...
        DependencyInsightsBackfill.create(github_owner_id: 1234)

        # Create Rails package so that we'll assign a package_id
        factory.given_package("rails", "4.2.0", :rubygems)
      end

      it "does not create new PackageReleaseDependentCounts because manifest can be superseded" do
        # Add a Gemfile to our sink to ensure that we actually skip manifests that can be superseded.
        expect { load_manifests([gemfile]) }
          .to_not change { Views::PackageReleaseDependentCount.count }
      end

      it "creates new PackageReleaseDependentCounts" do
        # Add a Gemfile.lock to our sink so that we'll get dependencies with an exact_version set.
        expect { load_manifests([gemfile_lock]) }
          .to change { Views::PackageReleaseDependentCount.count }.by(1)
      end

      it "writes to ManifestEntries, reads from ManifestEntries, and updates Dependency Insights without N+1 queries" do
        expect { load_manifests([gemfile_lock]) }
          # The number of these queries should not scale with the number of dependencies in gemfile_lock
          .to make_database_queries(matching: /SELECT `dg_manifest_package_versions`/, count: 2)
          .and make_database_queries(matching: /SELECT `dg_manifest_packages`/, count: 2)
          .and change { Views::PackageReleaseDependentCount.count }.by 1

        manifest = get_manifest(repo_id: 600, ref: "2c3ed2")

        manifest_entries = ManifestEntry.where(manifest: manifest)
        expect(manifest_entries.count).to eq 3

        manifest_dependencies = ManifestDependency.where(manifest: manifest)
        expect(manifest_dependencies.count).to eq 0
      end
    end

    it "skips the manifest if the repository NWO is blocklisted" do
      Ingest::Blocklist.clear(type: :manifest_repos)
      Ingest::Blocklist.add(type: :manifest_repos, item: "this_is/abadrepo")

      manifest_1 = manifest(
        filename: "pom.xml",
        github_repository_id: 600,
        github_owner_id: 1234,
        repository_nwo: "this_is/abadrepo",
        visibility_private: false,
      )

      expect {
        load_manifests([manifest_1])
      }.to_not change { Manifest.count }

      Ingest::Blocklist.clear(type: :manifest_repos)
    end

    it "loads packages from public actions manifests" do
      expect(Package.count).to be_zero
      # This stub is for a client call to Spokes to verify that a given object exists in a repo.
      allow_any_instance_of(BlobOperations::Spokes::Client).to receive(:object_exists?).and_return(true)

      repo = Repository.create!(
              github_repository_id: 600,
              github_owner_id: 1234,
              nwo: "working/workwork",
              public: true,
            )

      action_repo = Repository.create!(
                      github_repository_id: 700,
                      github_owner_id: 1234,
                      nwo: "working/myaction",
                      public: true,
                    )

      content = <<~YAML
      jobs:
        first_job:
          steps:
          - uses: working/myaction@v1
      YAML

      actions_manifest = manifest(
        path: ".github/workflows/",
        filename: "a_workflow.yml",
        github_repository_id: repo.github_repository_id,
        github_owner_id: repo.github_owner_id,
        repository_nwo: repo.nwo,
        content: content,
        visibility_private: !repo.public,
      )

      perform_enqueued_jobs do
        load_manifests([actions_manifest])
      end

      expect(Package.count).to eq 1
      expect(Package.first.name).to eq "working/myaction"
    end

    it "does not load packages from private actions manifests" do
      expect(Package.count).to be_zero

      repo = Repository.create!(
        github_repository_id: 601,
        github_owner_id: 1234,
        nwo: "working/morework",
        public: false,
      )

      actions_manifest = manifest(
        path: ".github/workflows/",
        filename: "a_workflow.yml",
        github_repository_id: repo.github_repository_id,
        github_owner_id: repo.github_owner_id,
        repository_nwo: repo.nwo,
        content: file_fixture("workflow.yaml").read,
        visibility_private: !repo.public,
      )

      perform_enqueued_jobs do
        load_manifests([actions_manifest])
      end

      expect(Package.count).to be_zero
    end

    it "does not load public actions packages on enterprise" do
      allow(DependencyGraphAPI).to receive(:enterprise?).and_return(true)

      repo = Repository.create!(
              github_repository_id: 600,
              github_owner_id: 1234,
              nwo: "working/workwork",
              public: true,
            )

      action_repo = Repository.create!(
                      github_repository_id: 700,
                      github_owner_id: 1234,
                      nwo: "working/myaction",
                      public: true,
                    )

      content = <<~YAML
      jobs:
        first_job:
          steps:
          - uses: working/myaction@v1
      YAML

      actions_manifest = manifest(
        path: ".github/workflows/",
        filename: "a_workflow.yml",
        github_repository_id: repo.github_repository_id,
        github_owner_id: repo.github_owner_id,
        repository_nwo: repo.nwo,
        content: content,
        visibility_private: !repo.public,
      )

      perform_enqueued_jobs do
        load_manifests([actions_manifest])
      end

      expect(Package.count).to eq 0
    end

    it "does not attempt to load packages from other manifests" do
      expect(Package.count).to be_zero
      load_manifests([a_manifest])

      expect(ActionsPackageJob).to_not have_been_enqueued
      expect(Package.count).to be_zero
    end

    it "handles named versions as manifest dependencies" do
      actions_manifest = ManifestAdapters::Manifest.new(
        package_manager: :actions,
        manifest_type: :workflow_yaml,
        git_ref: "2c3ed2",
        github_repository_id: 600,
        github_owner_id: 1234,
        repository_nwo: "github/github",
        repository_stargazer_count: 12,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "stuff.yaml",
        path: "./github/workflows/",
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
          package_name: "actions/checkout",
          requirements: "= main",
          scope: Types::Scope[:runtime],
        ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "productive/stuff",
            requirements: "= 1.2.3",
            scope: Types::Scope[:runtime],
          ),
        ],
      )

      load_manifests([actions_manifest])

      dependencies = get_manifest(repo_id: 600, ref: "2c3ed2")
        .entries

      checkout = dependencies.with_package_name("actions/checkout").first
      stuff = dependencies.with_package_name("productive/stuff").first

      expect(checkout.package_name).to eq "actions/checkout"
      expect(checkout.requirements).to eq "= main"
      expect(checkout.package_manager).to eq Types::PackageManager[:actions]
      expect(checkout.requirement_set.exact_version).to eq "main"

      expect(stuff.package_name).to eq "productive/stuff"
      expect(stuff.requirements).to eq "= 1.2.3"
      expect(stuff.package_manager).to eq Types::PackageManager[:actions]
      expect(stuff.requirement_set.exact_version).to eq "1.2.3"
    end

    it "instruments load.error when a parsing failure occurs" do
      loader = ManifestLoader.new(a_manifest)

      # This can be any method called by ManifestLoader#load
      allow(loader).to receive(:save_star_counts).and_raise(StandardError.new("Error saving star counts"))
      allow(Rails.application.stats).to receive(:increment)

      expect(Failbot).to receive(:report).with(StandardError)
      loader.load

      expect(Rails.application.stats).to have_received(:increment).with(
        "etl.manifests.load.error",
        tags: ["package_manager:rubygems", "error:StandardError"])
    end

    it "does not report to Failbot if the error is a retryable error" do
      loader = ManifestLoader.new(a_manifest)

      # This can be any method called by ManifestLoader#load
      allow(loader).to receive(:save_star_counts).and_raise(
        Errno::ETIMEDOUT
      )
      allow(Rails.application.stats).to receive(:increment)

      expect(Failbot).to_not receive(:report)
      expect { loader.load }.to raise_error(Errno::ETIMEDOUT)

      expect(Rails.application.stats).to have_received(:increment).with(
        "etl.manifests.load.error",
        tags: ["package_manager:rubygems", "error:Errno::ETIMEDOUT"])
    end

    it "cached dependents count for unchanged dependencies should remain unchanged" do
      [[2, "object-assign", "0.0.1"], [2, "object-assign", "0.0.2"], [2, "react", "0.0.1"]].each do |manager, name, version|
        package = Package.find_or_create_by(name: name)
        package.releases.create(name: version, package_manager: manager, package_name: name)
      end
      object_assign_1 = PackageRelease.find_by(package_name: "object-assign", name: "0.0.1")
      object_assign_2 = PackageRelease.find_by(package_name: "object-assign", name: "0.0.2")
      react_1 = PackageRelease.find_by(package_name: "react", name: "0.0.1")

      Repository.create!(
        github_repository_id: 1,
        github_owner_id: 1,
        nwo: "github/github",
        public: false
      )

      DependencyInsightsBackfill.create!(github_owner_id: 1)

      load_manifests([ManifestAdapters::Manifest.new(
        package_manager: :npm,
        manifest_type: :package_lock_json,
        git_ref: "a",
        github_repository_id: 1,
        github_owner_id: 1,
        repository_nwo: "github/github",
        repository_stargazer_count: 1,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "package-lock.json",
        path: "/",
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "object-assign",
            requirements: "= 0.0.1",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "react",
            requirements: "= 0.0.1",
            scope: Types::Scope[:runtime],
          ),
        ],
      )])

      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: object_assign_1.id).count).to eq(1)
      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: object_assign_2.id)).to eq(nil)
      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: react_1.id).count).to eq(1)

      travel_to 1.minute.from_now

      load_manifests([ManifestAdapters::Manifest.new(
        package_manager: :npm,
        manifest_type: :package_lock_json,
        git_ref: "b",
        github_repository_id: 1,
        github_owner_id: 1,
        repository_nwo: "github/github",
        repository_stargazer_count: 1,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 02),
        filename: "package-lock.json",
        path: "/",
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "object-assign",
            requirements: "= 0.0.2",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "react",
            requirements: "= 0.0.1",
            scope: Types::Scope[:runtime],
          ),
        ],
      )])

      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: object_assign_1.id)).to eq(nil)
      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: object_assign_2.id).count).to eq(1)
      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: react_1.id).count).to eq(1)
    end

    it "cached dependents count should only include exact requirements" do
      [[2, "object-assign", "0.0.1"], [2, "react", "0.0.1"]].each do |manager, name, version|
        package = Package.find_or_create_by(name: name)
        package.releases.create(name: version, package_manager: manager, package_name: name)
      end
      object_assign_1 = PackageRelease.find_by(package_name: "object-assign", name: "0.0.1")
      react_1 = PackageRelease.find_by(package_name: "react", name: "0.0.1")

      Repository.create!(
        github_repository_id: 1,
        github_owner_id: 1,
        nwo: "github/github",
        public: false
      )

      DependencyInsightsBackfill.create!(github_owner_id: 1)

      load_manifests([ManifestAdapters::Manifest.new(
        package_manager: :npm,
        manifest_type: :package_lock_json,
        git_ref: "a",
        github_repository_id: 1,
        github_owner_id: 1,
        repository_nwo: "github/github",
        repository_stargazer_count: 1,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 01),
        filename: "package-lock.json",
        path: "/",
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "object-assign",
            requirements: ">= 0.0.1",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "react",
            requirements: "= 0.0.1",
            scope: Types::Scope[:runtime],
          ),
        ],
      )])

      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: object_assign_1.id)).to eq(nil)
      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: react_1.id).count).to eq(1)

      travel_to 1.minute.from_now

      load_manifests([ManifestAdapters::Manifest.new(
        package_manager: :npm,
        manifest_type: :package_lock_json,
        git_ref: "b",
        github_repository_id: 1,
        github_owner_id: 1,
        repository_nwo: "github/github",
        repository_stargazer_count: 1,
        fork: false,
        visibility_private: false,
        pushed_at: Time.new(2017, 01, 02),
        filename: "package-lock.json",
        path: "/",
        dependent_name: nil,
        malformed: false,
        dependencies: [
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "object-assign",
            requirements: "= 0.0.1",
            scope: Types::Scope[:runtime],
          ),
          ManifestAdapters::Manifest::Dependency.new(
            package_name: "react",
            requirements: ">= 0.0.1",
            scope: Types::Scope[:runtime],
          ),
        ],
      )])

      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: object_assign_1.id).count).to eq(1)
      expect(Views::PackageReleaseDependentCount.find_by(github_owner_id: 1, package_release_id: react_1.id)).to eq(nil)
    end

  end
end
