require "rails_helper"

describe PackageRelease do
  describe ".newer_than" do
    it "returns releases newer than a given version" do
      oldest = factory.given_package("rake", "11.1.0").release
      older  = factory.given_package("rake", "11.2.0").release
      newer  = factory.given_package("rake", "11.3.0").release

      expect(described_class.newer_than(older)).to eq [newer]
    end

    it "for named version ecosystems, follow pre-existing ordering agreement" do
      # Named versions will be "newer" than semantic versions, semantic versions work as expected
      oldest = factory.given_package("actions/doing-things", "5.0.0", Types::PackageManager[:actions]).release
      older  = factory.given_package("actions/doing-things", "5.2.0", Types::PackageManager[:actions]).release
      newer  = factory.given_package("actions/doing-things", "main", Types::PackageManager[:actions]).release

      expect(described_class.newer_than(older, allow_named_versions: true)).to eq [newer]
      expect(described_class.newer_than(oldest, allow_named_versions: true).sort).to eq [older, newer]
    end

    it "handles prerelease versions" do
      older = factory.given_package("rake", "11.2.0-alpha").release
      newer = factory.given_package("rake", "11.2.0-beta").release

      expect(described_class.newer_than(older)).to eq [newer]
    end
  end

  describe ".latest_first" do
     it "returns the latest release" do
      oldest = factory.given_package("rake", "11.1.0").release
      older  = factory.given_package("rake", "11.2.0").release
      newer  = factory.given_package("rake", "11.3.0").release

      expect(described_class.latest_first.first).to eq newer
     end

     it "returns named version releases before semantic releases" do
      oldest = factory.given_package("actions/doing-things", "5.0.0", Types::PackageManager[:actions]).release
      older  = factory.given_package("actions/doing-things", "5.2.0", Types::PackageManager[:actions]).release
      newer  = factory.given_package("actions/doing-things", "main", Types::PackageManager[:actions]).release

      expect(described_class.latest_first.first).to eq newer
     end
  end

  describe ".matching_requirement_set" do
    before do
      factory do
        given_package("rake", "4.9.0")
        given_package("rake", "5.0.0")
        given_package("rake", "5.2.0")
        given_package("rake", "5.5.0")
        given_package("rake", "5.6.0")
      end
    end

    it "only includes releases within the version bounds" do
      range = Versioning::RequirementSet.new(
        ranges: [
          [Versioning::Requirement.new(">=", "5.5.0", allow_named_versions: false)],
        ], allow_named_versions: false
      )

      expect(described_class.matching_requirement_set(range)).to match_array([
        get_package_release("rake", "5.5.0"),
        get_package_release("rake", "5.6.0"),
      ])
    end

    it "supports compound requirements" do
      range = Versioning::RequirementSet.new(
        ranges: [
          [
            Versioning::Requirement.new(">=", "5.0.0", allow_named_versions: false),
            Versioning::Requirement.new("<", "5.5.0", allow_named_versions: false),
          ]
        ], allow_named_versions: false
      )

      expect(described_class.matching_requirement_set(range)).to match_array([
        get_package_release("rake", "5.0.0"),
        get_package_release("rake", "5.2.0"),
      ])
    end

    it "supports multiple requirements" do
      range = Versioning::RequirementSet.new(
        ranges: [
          [Versioning::Requirement.new(">", "5.5.0", allow_named_versions: false)],
          [Versioning::Requirement.new("<=", "5.0.0", allow_named_versions: false)],
        ], allow_named_versions: false
      )

      expect(described_class.matching_requirement_set(range)).to match_array([
        get_package_release("rake", "4.9.0"),
        get_package_release("rake", "5.0.0"),
        get_package_release("rake", "5.6.0"),
      ])
    end

    it "supports requirements containing named versions" do
      factory.given_package("actions/checkout", "main", Types::PackageManager[:actions])
      factory.given_package("actions/checkout", "dev", Types::PackageManager[:actions])

      ref_range = Versioning::RequirementSet.new(
        ranges: [
          [Versioning::Requirement.new("=", "main", allow_named_versions: true)],
        ],
        allow_named_versions: true,
      )

      expect(described_class.matching_requirement_set(ref_range)).to match_array([
        get_package_release("actions/checkout", "main"),
      ])

      semantic_range = Versioning::RequirementSet.new(
        ranges: [
          [Versioning::Requirement.new(">", "6.0.0", allow_named_versions: true)],
        ],
        allow_named_versions: true,
      )

      expect(described_class.matching_requirement_set(semantic_range)).to match_array([
        get_package_release("actions/checkout", "main"),
        get_package_release("actions/checkout", "dev"),
      ])
    end
  end

  describe "#parsed_version" do
    it "returns the semantic version" do
      release = described_class.new(name: "11.2.0-alpha")
      expect(release.parsed_version)
        .to eq Versioning::SemanticVersion.new(
          major: 11,
          minor: 2,
          patch: 0,
          prerelease: "alpha"
        )
    end

    it "returns the named version" do
      release = described_class.new(name: "main", package_manager: :actions)
      expect(release.parsed_version)
        .to eq Versioning::NamedVersion.new(
          name: "main",
        )
    end
  end

  describe ".class.find_metadata_by_batch_coords" do
    before do
      factory do
        given_package("rake", "4.9.0")
        given_package("rake", "5.0.0")
        given_package("rake", "5.2.0")
        given_package("rake", "5.5.0")
        given_package("rake", "5.6.0")
        given_package("lodash", "1.2.3", :npm)
        given_package("brodash", "2.4.5", :npm)
      end
    end

    it "happy path, batched lookup" do
      package_releases = described_class.find_metadata_by_batch_coords([
        {
          package_name: "rake",
          package_manager: Types::PackageManager[:rubygems],
          package_version: "4.9.0"
        },
        {
          package_name: "rake",
          package_manager: Types::PackageManager[:rubygems],
          package_version: "5.0.0"
        },
        { # this package will not be found, which is OK
          package_name: "rake",
          package_manager: Types::PackageManager[:rubygems],
          package_version: "5.1.0"
        }
      ])

      rake_4_9 = package_releases.find { |item| item.package_name == "rake" && item.name == "4.9.0" }
      rake_5_0 = package_releases.find { |item| item.package_name == "rake" && item.name == "5.0.0" }
      rake_5_1 = package_releases.find { |item| item.package_name == "rake" && item.name == "5.1.0" }

      expect(package_releases.count).to eq(2)

      expect(rake_4_9).to_not eq(nil)
      expect(rake_5_0).to_not eq(nil)
      expect(rake_5_1).to eq(nil)
    end

    it "dependency counts" do
      10.times do |i|
        # create ten dependents in a likely empty ID space
        create_npm_dependency("lodash", i + 1000)
      end
      9.times do |i|
        # create nine dependents in a likely empty ID space
        create_npm_dependency("brodash", i + 2000)
      end

      Views::AbstractRepositoryDependencyCount.update

      package_releases = described_class.find_metadata_by_batch_coords([
        {
          package_name: "lodash",
          package_manager: Types::PackageManager[:npm],
          package_version: "1.2.3"
        },
        {
          package_name: "brodash",
          package_manager: Types::PackageManager[:npm],
          package_version: "2.4.5"
        }
      ])

      lodash = package_releases.find { |item| item.package_name == "lodash" && item.name == "1.2.3" }
      brodash = package_releases.find { |item| item.package_name == "brodash" && item.name == "2.4.5" }

      expect(package_releases.count).to eq(2)

      expect(lodash.dependent_count).to eq(10)
      expect(brodash.dependent_count).to eq(9)
    end

    def create_npm_dependency(package_name, repository_id)
      # Why is this here? Because it changes something about how the tests run, and I'm not 100% sure what.
      # it appears that without it, a handful of unrelated test cases begin failing. This could be impacting
      # some sort of load or factory ordering, but I don't understand it and it started happening as code
      # was DELETED from this spec.
      AbstractPackageDependency.class
      repo = find_or_create_repo_by_id(repository_id)

      AbstractRepositoryDependency.create!({
        repository_id:   repository_id,
        package_manager: :npm,
        package_name:    package_name,
      })
    end

    def find_or_create_repo_by_id(repository_id)
      Repository.find_or_create_by(id: repository_id, github_repository_id: repository_id)
    end
  end
end
