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

  describe "#license" do
    [
      { original: "OTHER", expected: "LicenseRef-github-OTHER" },
      { original: "NOASSERTION", expected: "LicenseRef-github-NOASSERTION" },
      { original: "NONE", expected: "LicenseRef-github-NONE" },
      { original: "other", expected: "LicenseRef-github-OTHER" },
      { original: "noassertion", expected: "LicenseRef-github-NOASSERTION" },
      { original: "none", expected: "LicenseRef-github-NONE" },
      { original: "OTHER OR NOASSERTION AND NONE", expected: "LicenseRef-github-OTHER OR LicenseRef-github-NOASSERTION AND LicenseRef-github-NONE" },
      { original: "MIT", expected: "MIT" },
      { original: "ANOTHER OR OTHER OR MIT", expected: "ANOTHER OR LicenseRef-github-OTHER OR MIT" },
      { original: "OTHER-Text AND MIT", expected: "OTHER-Text AND MIT" },
      { original: "other-Text", expected: "other-Text" }

    ].each do |test_case|
      it "transforms #{test_case[:original]} to #{test_case[:expected]}" do
        release = factory.given_package("rake", "1.0.0").release
        release.update!(license: test_case[:original])
        # read_attribute checks raw database value, which should remain unchanged
        expect(release.read_attribute(:license)).to eq(test_case[:original])
        expect(release.license).to eq(test_case[:expected])
      end
    end

    it "handles nil licenses" do
      release = factory.given_package("rake", "1.0.0").release
      release.update!(license: nil)
      expect(release.read_attribute(:license)).to be_nil
      expect(release.license).to be_nil
    end

    describe "with dependency_graph_license_fixes feature flag enabled" do
      before do
        DependencyGraph.flipper.enable(:dependency_graph_license_fixes)
      end

      after do
        DependencyGraph.flipper.disable(:dependency_graph_license_fixes)
      end

      describe "scancode junk removal" do
        [
          {
            original: "MIT AND LicenseRef-scancode-unknown-license-reference",
            expected: "MIT",
            description: "removes scancode junk when ANDed with valid license"
          },
          {
            original: "BSD-3-Clause AND LicenseRef-scancode-unknown-license-reference",
            expected: "BSD-3-Clause",
            description: "removes scancode junk when ANDed with hyphenated license"
          },
          {
            original: "LicenseRef-scancode-free-unknown AND Apache-2.0",
            expected: "Apache-2.0",
            description: "removes scancode junk at the beginning"
          },
          {
            original: "BSD-3-Clause AND LicenseRef-scancode-generic-cla AND MIT",
            expected: "BSD-3-Clause AND MIT",
            description: "removes scancode junk in the middle"
          },
          {
            original: "LicenseRef-scancode-other-permissive AND LicenseRef-scancode-warranty-disclaimer AND GPL-3.0",
            expected: "GPL-3.0",
            description: "removes multiple scancode junk licenses"
          },
          {
            original: "LicenseRef-scancode-unknown-license-reference",
            expected: "LicenseRef-scancode-unknown-license-reference",
            description: "keeps scancode junk when it's the only license"
          },
        ].each do |test_case|
          it test_case[:description] do
            release = factory.given_package("test-package", "1.0.0").release
            release.update!(license: test_case[:original])
            expect(release.license).to eq(test_case[:expected])
          end
        end
      end

      describe "invalid SPDX string transformation" do
        [
          {
            original: "Standard 'no charge' license: https://gsap.com/standard-license",
            expected: "LicenseRef-bad-standard-no-charge-license-httpsgsap.comstandard-license",
            description: "transforms GSAP license to valid LicenseRef"
          },
          {
            original: "Custom License (C) 2023",
            expected: "LicenseRef-bad-custom-license-c-2023",
            description: "handles parentheses and copyright symbols"
          },
          {
            original: "See LICENSE.txt for details!",
            expected: "LicenseRef-bad-see-license.txt-for-details",
            description: "handles special characters and keeps periods"
          },
          {
            original: "MIT",
            expected: "MIT",
            description: "leaves valid SPDX licenses unchanged"
          },
          {
            original: "Apache-2.0 OR MIT",
            expected: "Apache-2.0 OR MIT",
            description: "leaves valid SPDX expressions unchanged"
          },
        ].each do |test_case|
          it test_case[:description] do
            release = factory.given_package("test-package", "1.0.0").release
            release.update!(license: test_case[:original])
            expect(release.license).to eq(test_case[:expected])
          end
        end

        it "limits transformed licenses to 255 characters" do
          long_license = "Custom " + ("a" * 300) + " License"
          release = factory.given_package("test-package", "1.0.0").release
          release.update!(license: long_license)
          expect(release.license.length).to be <= 255
          expect(release.license).to start_with("LicenseRef-bad-")
        end
      end

      describe "combined transformations" do
        it "applies OTHER/NONE/NOASSERTION transformation, removes scancode junk, and transforms invalid strings" do
          release = factory.given_package("test-package", "1.0.0").release
          release.update!(license: "OTHER AND LicenseRef-scancode-unknown-license-reference")
          # First transforms OTHER, then removes scancode junk, then checks if valid (it is after removing junk)
          expect(release.license).to eq("LicenseRef-github-OTHER")
        end

        it "handles scancode junk with invalid overall expression" do
          # If after removing scancode junk, the result is still invalid, it gets transformed
          release = factory.given_package("test-package", "1.0.0").release
          release.update!(license: "Some Custom License! AND LicenseRef-scancode-free-unknown")
          # After removing scancode junk: "Some Custom License!"
          # That's invalid SPDX, so it becomes LicenseRef-bad-*
          expect(release.license).to start_with("LicenseRef-bad-")
        end
      end

      it "does not modify the raw database value" do
        release = factory.given_package("test-package", "1.0.0").release
        original = "MIT AND LicenseRef-scancode-unknown-license-reference"
        release.update!(license: original)
        expect(release.read_attribute(:license)).to eq(original)
        expect(release.license).to eq("MIT")
      end
    end

    describe "with dependency_graph_license_fixes feature flag disabled" do
      before do
        DependencyGraph.flipper.disable(:dependency_graph_license_fixes)
      end

      it "does not remove scancode junk" do
        release = factory.given_package("test-package", "1.0.0").release
        original = "MIT AND LicenseRef-scancode-unknown-license-reference"
        release.update!(license: original)
        # Only applies the standard OTHER/NONE/NOASSERTION transformation
        expect(release.license).to eq(original)
      end

      it "does not transform invalid SPDX strings" do
        release = factory.given_package("test-package", "1.0.0").release
        original = "Standard 'no charge' license: https://gsap.com/standard-license"
        release.update!(license: original)
        # Only applies the standard OTHER/NONE/NOASSERTION transformation (which doesn't match here)
        expect(release.license).to eq(original)
      end
    end
  end

  describe ".remove_scancode_junk" do
    it "removes scancode junk when ANDed at the end" do
      expect(described_class.remove_scancode_junk("MIT AND LicenseRef-scancode-unknown-license-reference")).to eq("MIT")
    end

    it "removes scancode junk when ANDed at the beginning" do
      expect(described_class.remove_scancode_junk("LicenseRef-scancode-free-unknown AND Apache-2.0")).to eq("Apache-2.0")
    end

    it "removes scancode junk in the middle" do
      expect(described_class.remove_scancode_junk("BSD-3-Clause AND LicenseRef-scancode-generic-cla AND MIT")).to eq("BSD-3-Clause AND MIT")
    end

    it "removes multiple scancode junk licenses" do
      expect(described_class.remove_scancode_junk("LicenseRef-scancode-other-permissive AND LicenseRef-scancode-warranty-disclaimer AND GPL-3.0")).to eq("GPL-3.0")
    end

    it "keeps scancode junk when it's the only license" do
      expect(described_class.remove_scancode_junk("LicenseRef-scancode-unknown-license-reference")).to eq("LicenseRef-scancode-unknown-license-reference")
    end

    it "returns nil for nil input" do
      expect(described_class.remove_scancode_junk(nil)).to be_nil
    end

    it "does not affect OR expressions" do
      expect(described_class.remove_scancode_junk("MIT OR LicenseRef-scancode-unknown-license-reference")).to eq("MIT OR LicenseRef-scancode-unknown-license-reference")
    end
  end

  describe ".transform_invalid_to_license_ref" do
    it "transforms invalid license string to LicenseRef-bad- format" do
      result = described_class.transform_invalid_to_license_ref("Standard 'no charge' license: https://gsap.com/standard-license")
      expect(result).to eq("LicenseRef-bad-standard-no-charge-license-httpsgsap.comstandard-license")
    end

    it "converts spaces to hyphens" do
      result = described_class.transform_invalid_to_license_ref("Custom License")
      expect(result).to eq("LicenseRef-bad-custom-license")
    end

    it "converts alpha characters to lowercase" do
      result = described_class.transform_invalid_to_license_ref("CUSTOM LICENSE")
      expect(result).to eq("LicenseRef-bad-custom-license")
    end

    it "keeps numbers, hyphens, and periods" do
      result = described_class.transform_invalid_to_license_ref("License-2.0.1")
      expect(result).to eq("LicenseRef-bad-license-2.0.1")
    end

    it "drops special characters" do
      result = described_class.transform_invalid_to_license_ref("License! @#$% ^&*()")
      expect(result).to eq("LicenseRef-bad-license")
    end

    it "limits length to 255 characters" do
      long_license = "Custom " + ("a" * 300) + " License"
      result = described_class.transform_invalid_to_license_ref(long_license)
      expect(result.length).to eq(255)
      expect(result).to start_with("LicenseRef-bad-")
    end

    it "returns valid SPDX licenses unchanged" do
      expect(described_class.transform_invalid_to_license_ref("MIT")).to eq("MIT")
      expect(described_class.transform_invalid_to_license_ref("Apache-2.0")).to eq("Apache-2.0")
      expect(described_class.transform_invalid_to_license_ref("MIT OR Apache-2.0")).to eq("MIT OR Apache-2.0")
    end

    it "returns nil for nil input" do
      expect(described_class.transform_invalid_to_license_ref(nil)).to be_nil
    end
  end

  describe ".valid_spdx?" do
    it "returns true for valid SPDX license identifiers" do
      expect(described_class.valid_spdx?("MIT")).to be true
      expect(described_class.valid_spdx?("Apache-2.0")).to be true
      expect(described_class.valid_spdx?("GPL-3.0-or-later")).to be true
    end

    it "returns true for valid SPDX license expressions" do
      expect(described_class.valid_spdx?("MIT OR Apache-2.0")).to be true
      expect(described_class.valid_spdx?("MIT AND Apache-2.0")).to be true
    end

    it "returns false for invalid SPDX strings" do
      expect(described_class.valid_spdx?("Custom License")).to be false
      expect(described_class.valid_spdx?("See LICENSE.txt")).to be false
    end

    it "returns false for nil or empty strings" do
      expect(described_class.valid_spdx?(nil)).to be false
      expect(described_class.valid_spdx?("")).to be false
    end

    it "returns false when Spdx.valid? raises an error" do
      allow(Spdx).to receive(:valid?).and_raise(StandardError.new("Test error"))
      expect(described_class.valid_spdx?("MIT")).to be false
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
