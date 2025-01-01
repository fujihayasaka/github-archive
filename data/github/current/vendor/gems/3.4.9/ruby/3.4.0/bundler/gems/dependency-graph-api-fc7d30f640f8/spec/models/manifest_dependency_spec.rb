require "rails_helper"

describe ManifestDependency do
  def version_range(lower_bound:, upper_bound:)
    Versioning::VersionRange.new(
      lower_bound: Versioning::SemanticVersion.new(**lower_bound),
      upper_bound: Versioning::SemanticVersion.new(**upper_bound),
    )
  end

  describe "#overlap?" do
    it "is true if requirements are within the range" do
      included = factory.given_manifest_dependency({
        package_name: "rails",
        requirements: "= 5.1.0"
      })

      expect(included.overlap?(version_range(
        lower_bound: {
          major: 5,
          minor: 0,
          patch: 0,
        },
        upper_bound: {
          major: 5,
          minor: 2,
          patch: 0,
        }
      ))).to be_truthy
    end

    it "is false if requirements fall below the lower bound" do
      excluded = factory.given_manifest_dependency({
        package_name: "rails",
        requirements: "~> 5.0.0"
      })

      expect(excluded.overlap?(version_range(
        lower_bound: {
          major: 5,
          minor: 1,
          patch: 0,
        },
        upper_bound: {
          major: 5,
          minor: 2,
          patch: 0,
        }
      ))).to be_falsey
    end

    it "is false if requirements fall above the upper bound" do
      excluded = factory.given_manifest_dependency({
        package_name: "rails",
        requirements: "> 5.2.0"
      })

      expect(excluded.overlap?(version_range(
        lower_bound: {
          major: 5,
          minor: 1,
          patch: 0,
        },
        upper_bound: {
          major: 5,
          minor: 2,
          patch: 0,
        }
      ))).to be_falsey
    end
  end

  context ".latest_revisions" do
    let(:old_rev) {
      factory.given_manifest_dependency({
        package_name: "rails",
        requirements: "= 5.1.0",
        last_seen_at_revision: 2
      })
    }

    let(:manifest) { old_rev.manifest }

    let(:new_rev) {
      factory.given_manifest_dependency({
        manifest: manifest,
        package_name: "rails",
        requirements: "= 5.2.0",
        last_seen_at_revision: 3
      })
    }

    # factories hardcode a revision, let's set one here for the tests
    before do
      manifest.update(revision: 3)
    end

    it "only includes the latest revision of each dependency" do
      result = ManifestDependency.latest_revisions

      expect(result).to include(new_rev)
      expect(result).not_to include(old_rev)
    end
  end
end
