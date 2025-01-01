require "rails_helper"

module Queries
  RSpec.shared_examples "a version range dependents query" do
    describe "#valid?" do
      it "is true if the requirements are well-formed" do
        expect(described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )).to be_valid
      end

      it "allows bounds omissions" do
        expect(described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    "<= 5.1.0",
        )).to be_valid

        expect(described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0",
        )).to be_valid
      end

      it "is false if the package name is missing" do
        expect(described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    nil,
          requirements:    ">= 5.0.0, <= 5.1.0",
        )).to_not be_valid

        expect(described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )).to_not be_valid
      end

      it "is false if the package manager is missing" do
        expect(described_class.new(
          package_manager: nil,
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )).to_not be_valid

        expect(described_class.new(
          package_manager: "",
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )).to_not be_valid
      end

      it "is false if the requirements are malformed" do
        expect(described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    "CATS"
        )).to_not be_valid
      end
    end

    describe "#has_next?" do
      it "is true if there are results beyond the current page" do
        factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )

        expect(query.first(1)).to have_next
      end

      it "is false if there are no results beyond the current page" do
        factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rake", requirements: ">= 0.0.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )

        expect(query.first(1)).to_not have_next
      end

      it "is false if all remaining results are disqualified" do
        factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 4.2.0" },
          ]
        ).get

        factory.given_manifest(
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "4.2.11" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 4.0.0, <= 4.1.0",
        )

        expect(query.first(1)).not_to have_next
        expect(query.first(2)).not_to have_next
        expect(query.first(3)).not_to have_next
      end
    end

    describe "#has_previous?" do
      it "is true if there are results before the current page" do
        first = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )

        cursor = first.dependencies.first.to_cursor
        expect(query.after(cursor)).to have_previous
      end

      it "is false if there are no results before the current page" do
        factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )
        expect(query).to_not have_previous
      end
    end

    describe "#estimated_dependent_repository_count" do
      it "returns the count of manifests with dependents" do
        factory do
          given_manifest(
            github_repo_id: 100,
            manifest_type:  :gemfile,
            filename:       "Gemfile",
            path:           "/",
            dependencies:   [
              { package_name: "rails", requirements: "~> 5.0.0" },
            ]
          )

          # Belongs to same repo as above, should only count once
          given_manifest(
            github_repo_id: 100,
            manifest_type:  :gemfile_lock,
            filename:       "Gemfile.lock",
            path:           "/",
            dependencies:   [
              { package_name: "rails", requirements: "= 5.0.5" },
            ]
          )

          given_manifest(
            github_repo_id: 200,
            manifest_type:  :gemfile,
            filename:       "Gemfile",
            path:           "/",
            dependencies:   [
              { package_name: "rails", requirements: "~> 5.0.0" },
            ]
          )

          # Excluded by package
          given_manifest(
            github_repo_id: 300,
            manifest_type:  :gemfile,
            filename:       "Gemfile",
            path:           "/",
            dependencies:   [
              { package_name: "rake", requirements: "> 0.0.0" },
            ]
          )
        end

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )

        expect(query.estimated_dependent_repository_count).to eq 3
      end
    end

    context "empty page support" do
      it "returns no nodes but has next page" do
        manifest1 = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          revision:       11,
          dependencies:   [
            {
              package_name: "rails",
              requirements: "= 4.0.1",
              last_seen_at_revision: 10
            }
          ]
        ).get

        manifest2 = factory.given_manifest(
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision:       12,
          dependencies:   [
            {
              package_name: "rails",
              requirements: "= 4.0.2",
              last_seen_at_revision: 11
            }
          ]
        ).get

        manifest3 = factory.given_manifest(
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision:       13,
          dependencies:   [
            {
              package_name: "rails",
              requirements: "= 4.0.3",
              last_seen_at_revision: 12
            }
          ]
        ).get

        query = described_class.new(
          package_manager:   Types::PackageManager[:rubygems],
          package_name:      "rails",
          requirements:      ">= 4.0.0, <= 4.1.0",
        ).first(1)

        expect(query).to have_next
        expect(query.dependents).to be_empty
        expect(query.last_dependent.manifest).to eq(manifest1)

        query = described_class.new(
          package_manager:   Types::PackageManager[:rubygems],
          package_name:      "rails",
          requirements:      ">= 4.0.0, <= 4.1.0",
        ).first(2)

        expect(query).to have_next
        expect(query.dependents).to be_empty
        expect(query.last_dependent.manifest).to eq(manifest2)

        query = described_class.new(
          package_manager:   Types::PackageManager[:rubygems],
          package_name:      "rails",
          requirements:      ">= 4.0.0, <= 4.1.0",
        ).first(3)

        expect(query).not_to have_next
        expect(query.dependents).to be_empty
        expect(query.last_dependent).to be_nil
      end

      it "returns the last possibly disqualified dependent" do
        manifest1 = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          revision:       11,
          dependencies:   [
            {
              package_name: "rails",
              requirements: "= 4.2.1",
              last_seen_at_revision: 11
            }
          ]
        ).get

        manifest2 = factory.given_manifest(
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision:       12,
          dependencies:   [
            {
              package_name: "rails",
              requirements: "= 4.2.2",
              last_seen_at_revision: 11
            }
          ]
        ).get

        manifest3 = factory.given_manifest(
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision:       13,
          dependencies:   [
            {
              package_name: "rails",
              requirements: "= 4.2.3",
              last_seen_at_revision: 13
            }
          ]
        ).get

        manifest4 = factory.given_manifest(
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision:       14,
          dependencies:   [
            {
              package_name: "rails",
              requirements: "= 4.2.4",
              last_seen_at_revision: 14
            }
          ]
        ).get

        query = described_class.new(
          package_manager:   Types::PackageManager[:rubygems],
          package_name:      "rails",
          requirements:      ">= 4.2.0",
        ).first(2)

        expect(query).to have_next
        expect(query.dependents.map(&:manifest)).to eq([manifest1])
        expect(query.last_dependent.manifest).to eq(manifest2)

        query = described_class.new(
          package_manager:   Types::PackageManager[:rubygems],
          package_name:      "rails",
          requirements:      ">= 4.2.0",
        ).first(3)

        expect(query).to have_next
        expect(query.dependents.map(&:manifest)).to eq([manifest1, manifest3])
        expect(query.last_dependent.manifest).to eq(manifest3)
      end
    end
  end

  class NormalizedVersionRangeDependentsQuery < Queries::VersionRangeDependentsQuery
    def initialize(**args)
      super(use_normalized_tables: true, **args)
    end
  end

  describe VersionRangeDependentsQuery do
    it_should_behave_like "a version range dependents query"

    describe "#dependents" do
      def via_serialized_requirements(options = {})
        described_class.new(**{
          package_manager:         Types::PackageManager[:rubygems],
          package_name:            "rails",
          requirements: ">= 5.0.0, <= 5.1.0"
        }.merge(options))
      end

      it "includes dependencies with requirements within the range" do
        included = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
            # Ignore dependencies on other package
            { package_name: "rake", requirements: "= 5.1.0" },
          ]
        ).get

        expect(via_serialized_requirements.dependents)
          .to eq(included.dependencies.with_package_name("rails"))
      end

      it "excludes dependencies without manifests" do
        manifest = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get
        missing_manifest = factory.given_manifest(
          github_repo_id: 200,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        missing_manifest.delete

        expect(via_serialized_requirements.dependents)
          .to eq(manifest.dependencies.with_package_name("rails"))
      end

      it "excludes dependencies from other package managers" do
        included = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :package_json,
          filename:       "package.json",
          path:           "/",
          package_manager: Types::PackageManager[:npm],
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        expect(via_serialized_requirements.dependents).to eq []
      end

      it "excludes dependencies with requirements outside the range" do
        gemfile = factory.given_manifest(
          github_repo_id: 200,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            # Ignore dependencies on unaffected versions
            { package_name: "rails", requirements: "~> 4.2.0" },
            { package_name: "rake", requirements: "= 5.1.0" },
          ]
        ).get

        expect(via_serialized_requirements.dependents).to eq []
      end

      it "excludes dependencies that are subtley outside the range" do
        gemfile = factory.given_manifest(
          github_repo_id: 300,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            # The encoded form of requirements doesn't express the nuance of
            # semver pre-release behavior, where '5.0.0.alpha' < '5.0.0'. We
            # have to filter out this dependency on the application side.
            { package_name: "rails", requirements: "= 5.0.0.alpha" },
          ]
        ).get

        expect(via_serialized_requirements.dependents).to eq []
      end

      it "respects limits and ID offset" do
        batch_1 = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        batch_2 = factory.given_manifest(
          github_repo_id: 200,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.1.0" },
          ]
        ).get

        range = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.2.0",
          limit:           1
        )

        expect(range.dependents)
          .to eq(batch_1.dependencies.with_package_name("rails"))

        range = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.2.0",
          limit:           1,
          after:           range.dependents.last.to_cursor
        )

        expect(range.dependents)
          .to eq(batch_2.dependencies.with_package_name("rails"))
      end

      it "ignores affected dependencies that are superseded by more specific requirements" do
        gemfile = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: ">= 5.0.0" },
          ]
        ).get

        gemfile_lock = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "= 5.1.0" },
          ]
        ).get

        excluded = gemfile.dependencies.with_package_name("rails").first
        expect(via_serialized_requirements.dependents).to_not include(excluded)
      end

      it "ignores dependencies aren't current" do
        gemfile = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          revision:       10,
          dependencies:   [
            # This dependency isn't present in the latest version of the Gemfile
            {
              package_name:          "rails",
              requirements:          ">= 5.0.0",
              last_seen_at_revision: 9
            },
          ]
        ).get

        excluded = gemfile.dependencies.with_package_name("rails")

        expect(via_serialized_requirements.dependents)
          .to_not include(excluded.first)
      end

      it "ignores dependencies in vendored manifests" do
        gemfile = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "vendor/gems",
          revision:       1,
          dependencies:   [
            {
              package_name:          "rails",
              requirements:          ">= 5.0.0",
              last_seen_at_revision: 1
            },
          ]
        ).get

        excluded = gemfile.dependencies.with_package_name("rails")

        expect(via_serialized_requirements.dependents)
          .to_not include(excluded.first)
      end

      it "doesn't issue unnecessary queries" do
        10.times do |i|
          factory.given_manifest(
            github_repo_id: i,
            manifest_type:  :gemfile,
            filename:       "Gemfile",
            path:           "/",
            revision:       1,
            dependencies:   [
              {
                package_name:          "rails",
                requirements:          ">= 5.0.0",
                last_seen_at_revision: 1
              },
            ]
          ).get
        end

        # One query to load dependencies
        # One possible query to eager load manifests
        # One possible query to eager load repositories
        # One query to load siblings
        expect {
          dependents = via_serialized_requirements.dependents
          dependents.map(&:github_repository_id)
        }.to make_database_queries(count: 0..4)
      end

      it "handles manifests with invalid version ranges" do
        gemfile = factory.given_manifest(
          github_repo_id: 200,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            # => is not a valid version string
            { package_name: "rails", requirements: "=> 4.2.0" },
          ]
        ).get

        # TODO FIX
        # our factories won't let us actually create a manifest dependency with an invalid requiremnt set
        dep = gemfile.dependencies.first
        dep.requirements = "=> 4.2.0"
        dep.save!

        query = described_class.new(
          package_manager:         Types::PackageManager[:rubygems],
          package_name:            "rails",
          requirements: ">= 5.0.0, <= 5.1.0",
        )

        expect(query.dependents).to eq []
      end

      it "handles query with invalid requirements when using version ranges" do
        manifest = factory.given_manifest(
          github_repo_id: 100,
          package_manager: Types::PackageManager[:actions],
          manifest_type:  :workflow_yaml,
          filename:       "doing-stuff.yml",
          path:           ".github/workflows/",
          dependencies:   [
            { package_name: "actions/checkout", requirements: "= dev" },
            { package_name: "actions/another", requirements: "= 5.1.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:actions],
          package_name:    "actions/checkout",
          requirements: "main", # an accurate requirement would be "= main"
        )

        expect(query.dependents)
          .to be_empty


        query2 = described_class.new(
          package_manager: Types::PackageManager[:actions],
          package_name:    "actions/checkout",
          requirements: "= main",
        )

        dep = manifest.dependencies.first
        dep.requirements = "dev" # an accurate requirement would be "= dev"
        dep.save!

        expect(query2.dependents)
        .to be_empty
      end

      context "handling named versions" do
        it "includes dependencies with requirements within the range" do
          included = factory.given_manifest(
            github_repo_id: 100,
            package_manager: Types::PackageManager[:actions],
            manifest_type:  :workflow_yaml,
            filename:       "doing-stuff.yml",
            path:           ".github/workflows/",
            dependencies:   [
              { package_name: "actions/checkout", requirements: "= dev" },
              # Ignore dependencies on other package
              { package_name: "actions/another", requirements: "= 5.1.0" },
            ]
          ).get

          query = via_serialized_requirements(
            package_manager: Types::PackageManager[:actions],
            package_name:    "actions/checkout",
            requirements:    ">= 5.0.0"
          )

          expect(query.dependents)
            .to eq(included.dependencies.with_package_name("actions/checkout"))
        end

        it "excludes dependencies with requirements outside the range" do
          excluded = factory.given_manifest(
            github_repo_id: 100,
            package_manager: Types::PackageManager[:actions],
            manifest_type:  :workflow_yaml,
            filename:       "doing-stuff.yml",
            path:           ".github/workflows/",
            dependencies:   [
              { package_name: "actions/checkout", requirements: "= dev" },
            ]
          ).get

          query = via_serialized_requirements(
            package_manager: Types::PackageManager[:actions],
            package_name:    "actions/checkout",
            requirements:    "<= 5.0.0"
          )

          expect(query.dependents).to eq []
        end
      end
    end

    describe "#after" do
      it "only returns results after the offset" do
        excluded = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        included = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )

        cursor = excluded.dependencies.first.to_cursor
        expect(query.after(cursor).dependents)
          .to eq included.dependencies
      end
    end

    describe "#first" do
      it "limits results" do
        included = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        excluded = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )

        expect(query.first(1).dependents)
          .to eq included.dependencies
      end
    end
  end

  describe NormalizedVersionRangeDependentsQuery do
    it_should_behave_like "a version range dependents query"

    describe "#dependents" do
      def via_serialized_requirements(options = {})
        described_class.new(**{
          package_manager:         Types::PackageManager[:rubygems],
          package_name:            "rails",
          requirements: ">= 5.0.0, <= 5.1.0"
        }.merge(options))
      end

      it "includes dependencies with requirements within the range" do
        included = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
            # Ignore dependencies on other package
            { package_name: "rake", requirements: "= 5.1.0" },
          ]
        ).get

        expect(via_serialized_requirements.dependents)
          .to eq(included.entries.filter { |e| e.manifest_package_version.manifest_package.package_name == "rails" })
      end

      it "excludes dependencies without manifests" do
        manifest = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get
        missing_manifest = factory.given_manifest(
          github_repo_id: 200,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        missing_manifest.delete

        expect(via_serialized_requirements.dependents)
          .to eq(manifest.entries.filter { |e| e.manifest_package_version.manifest_package.package_name == "rails" })
      end

      it "excludes dependencies from other package managers" do
        included = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :package_json,
          filename:       "package.json",
          path:           "/",
          package_manager: Types::PackageManager[:npm],
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        expect(via_serialized_requirements.dependents).to eq []
      end

      it "excludes dependencies with requirements outside the range" do
        gemfile = factory.given_manifest(
          github_repo_id: 200,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            # Ignore dependencies on unaffected versions
            { package_name: "rails", requirements: "~> 4.2.0" },
            { package_name: "rake", requirements: "= 5.1.0" },
          ]
        ).get

        expect(via_serialized_requirements.dependents).to eq []
      end

      it "excludes dependencies that are subtley outside the range" do
        gemfile = factory.given_manifest(
          github_repo_id: 300,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            # The encoded form of requirements doesn't express the nuance of
            # semver pre-release behavior, where '5.0.0.alpha' < '5.0.0'. We
            # have to filter out this dependency on the application side.
            { package_name: "rails", requirements: "= 5.0.0.alpha" },
          ]
        ).get

        expect(via_serialized_requirements.dependents).to eq []
      end

      it "respects limits and ID offset" do
        batch_1 = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        batch_2 = factory.given_manifest(
          github_repo_id: 200,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.1.0" },
          ]
        ).get

        range = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.2.0",
          limit:           1
        )

        expect(range.dependents)
          .to eq(batch_1.entries.filter { |e| e.manifest_package_version.manifest_package.package_name == "rails" })

        range = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.2.0",
          limit:           1,
          after:           range.dependents.last.to_cursor
        )

        expect(range.dependents)
          .to eq(batch_2.entries.filter { |e| e.manifest_package_version.manifest_package.package_name == "rails" })
      end

      it "ignores affected dependencies that are superseded by more specific requirements" do
        gemfile = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: ">= 5.0.0" },
          ]
        ).get

        gemfile_lock = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "= 5.1.0" },
          ]
        ).get

        excluded = gemfile.entries.find { |e| e.manifest_package_version.manifest_package.package_name == "rails" }
        expect(via_serialized_requirements.dependents).to_not include(excluded)
      end

      it "ignores dependencies aren't current" do
        gemfile = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          revision:       10,
          dependencies:   [
            # This dependency isn't present in the latest version of the Gemfile
            {
              package_name:          "rails",
              requirements:          ">= 5.0.0",
              last_seen_at_revision: 9
            },
          ]
        ).get

        excluded = gemfile.entries.find { |e| e.manifest_package_version.manifest_package.package_name == "rails" }

        expect(via_serialized_requirements.dependents)
          .to_not include(excluded)
      end

      it "ignores dependencies in vendored manifests" do
        gemfile = factory.given_manifest(
          github_repo_id: 100,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "vendor/gems",
          revision:       1,
          dependencies:   [
            {
              package_name:          "rails",
              requirements:          ">= 5.0.0",
              last_seen_at_revision: 1
            },
          ]
        ).get

        excluded = gemfile.dependencies.with_package_name("rails")

        expect(via_serialized_requirements.dependents)
          .to_not include(excluded.first)
      end

      it "doesn't issue unnecessary queries" do
        10.times do |i|
          factory.given_manifest(
            github_repo_id: i,
            manifest_type:  :gemfile,
            filename:       "Gemfile",
            path:           "/",
            revision:       1,
            dependencies:   [
              {
                package_name:          "rails",
                requirements:          ">= 5.0.0",
                last_seen_at_revision: 1
              },
            ]
          ).get
        end

        # One query to load dependencies
        # One possible query to eager load manifests
        # One possible query to eager load repositories
        # One query to load siblings
        expect {
          dependents = via_serialized_requirements.dependents
          dependents.map(&:github_repository_id)
        }.to make_database_queries(count: 0..4)
      end

      it "handles manifests with invalid version ranges" do
        gemfile = factory.given_manifest(
          github_repo_id: 200,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            # => is not a valid version string
            { package_name: "rails", requirements: "=> 4.2.0" },
          ]
        ).get

        # TODO FIX
        # our factories won't let us actually create a manifest dependency with an invalid requiremnt set
        dep = gemfile.dependencies.first
        dep.requirements = "=> 4.2.0"
        dep.save!

        query = described_class.new(
          package_manager:         Types::PackageManager[:rubygems],
          package_name:            "rails",
          requirements: ">= 5.0.0, <= 5.1.0",
        )

        expect(query.dependents).to eq []
      end

      it "handles query with invalid requirements when using version ranges" do
        manifest = factory.given_manifest(
          github_repo_id: 100,
          package_manager: Types::PackageManager[:actions],
          manifest_type:  :workflow_yaml,
          filename:       "doing-stuff.yml",
          path:           ".github/workflows/",
          dependencies:   [
            { package_name: "actions/checkout", requirements: "= dev" },
            { package_name: "actions/another", requirements: "= 5.1.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:actions],
          package_name:    "actions/checkout",
          requirements: "main", # an accurate requirement would be "= main"
        )

        expect(query.dependents)
          .to be_empty


        query2 = described_class.new(
          package_manager: Types::PackageManager[:actions],
          package_name:    "actions/checkout",
          requirements: "= main",
        )

        dep = manifest.dependencies.first
        dep.requirements = "dev" # an accurate requirement would be "= dev"
        dep.save!

        expect(query2.dependents)
        .to be_empty
      end

      context "handling named versions" do
        it "includes dependencies with requirements within the range" do
          included = factory.given_manifest(
            github_repo_id: 100,
            package_manager: Types::PackageManager[:actions],
            manifest_type:  :workflow_yaml,
            filename:       "doing-stuff.yml",
            path:           ".github/workflows/",
            dependencies:   [
              { package_name: "actions/checkout", requirements: "= dev" },
              # Ignore dependencies on other package
              { package_name: "actions/another", requirements: "= 5.1.0" },
            ]
          ).get

          query = via_serialized_requirements(
            package_manager: Types::PackageManager[:actions],
            package_name:    "actions/checkout",
            requirements:    ">= 5.0.0"
          )

          expect(query.dependents)
            .to eq(included.entries.filter { |e| e.manifest_package_version.manifest_package.package_name == "actions/checkout" })
        end

        it "excludes dependencies with requirements outside the range" do
          excluded = factory.given_manifest(
            github_repo_id: 100,
            package_manager: Types::PackageManager[:actions],
            manifest_type:  :workflow_yaml,
            filename:       "doing-stuff.yml",
            path:           ".github/workflows/",
            dependencies:   [
              { package_name: "actions/checkout", requirements: "= dev" },
            ]
          ).get

          query = via_serialized_requirements(
            package_manager: Types::PackageManager[:actions],
            package_name:    "actions/checkout",
            requirements:    "<= 5.0.0"
          )

          expect(query.dependents).to eq []
        end
      end
    end

    describe "#after" do
      it "only returns results after the offset" do
        excluded = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        included = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )

        cursor = excluded.entries.first.to_cursor
        expect(query.after(cursor).dependents)
          .to eq included.entries
      end
    end

    describe "#first" do
      it "limits results" do
        included = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        excluded = factory.given_manifest(
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies:   [
            { package_name: "rails", requirements: "~> 5.0.0" },
          ]
        ).get

        query = described_class.new(
          package_manager: Types::PackageManager[:rubygems],
          package_name:    "rails",
          requirements:    ">= 5.0.0, <= 5.1.0",
        )

        expect(query.first(1).dependents)
          .to eq included.entries
      end
    end
  end
end
