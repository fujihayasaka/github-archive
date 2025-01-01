require "rails_helper"

module Queries
  describe PackageQuery do
    describe "#results" do
      it "returns packages" do
        package = Package.create!({
          name: "httparty"
        })
        expect(results).to eq [package]
      end

      describe "scoping by repository_id" do
        it "scopes by repository ID" do
          package_1 = Package.create!({
            name:                    "httparty",
            package_manager:         :rubygems,
            github_repository_id:    1,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
          })
          create_corresponding_manifest_for_package(package_1)

          package_2 = Package.create!({
            name:                    "rake",
            package_manager:         :rubygems,
            github_repository_id:    2,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
          })
          create_corresponding_manifest_for_package(package_2)

          expect(results(repository_ids: 2))
            .to eq [package_2]

          expect(results(repository_ids: [1, 2]))
            .to match_array [package_1, package_2]
        end

        it "returns packages with the highest repo ID certainty" do
          package_1 = Package.create!({
            name:                    "httparty",
            package_manager:         :rubygems,
            github_repository_id:    10,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST
          })
          create_corresponding_manifest_for_package(package_1)

          package_2 = Package.create!({
            name:                    "httparty-copy",
            package_manager:         :rubygems,
            github_repository_id:    10,
            repository_id_certainty: PackageToRepoMapping::Certainty::UNVERIFIED
          })
          create_corresponding_manifest_for_package(package_2)

          package_3 = Package.create!({
            name:                 "httparty-another-copy",
            package_manager:      :rubygems,
            github_repository_id: 10,
          })
          create_corresponding_manifest_for_package(package_3)

          package_4 = Package.create!({
            name:                    "unrelated",
            package_manager:         :rubygems,
            github_repository_id:    15,
            repository_id_certainty: PackageToRepoMapping::Certainty::OVERRIDE,
          })
          create_corresponding_manifest_for_package(package_4)

          expect(results(repository_ids: 10))
            .to eq [package_1, package_2]
        end

        it "doesn't include packages without corresponding manifests in the repository" do
          included = Package.create!({
            name:                    "rails",
            package_manager:         :rubygems,
            github_repository_id:    15,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
          })
          create_corresponding_manifest_for_package(included)

          # A package published with incorrect repo metadata, perhaps
          excluded = Package.create!({
            name:                    "fake-rails",
            package_manager:         :rubygems,
            github_repository_id:    15,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
          })

          # A package published with incorrect repo metadata to another package manager
          excluded = Package.create!({
            name:                    "rails",
            package_manager:         :npm,
            github_repository_id:    15,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
          })

          expect(results(repository_ids: 15))
            .to eq [included]
        end

        it "includes packages without corresponding manifests when debugging" do
          included = Package.create!({
            name:                 "fake-rails",
            package_manager:      :rubygems,
            github_repository_id: 15,
          })

          expect(results(repository_ids: 15, debug: true))
            .to eq [included]
        end

        it "includes debug info about package+repo association when package should be associated to repo" do
          package_with_manifest = Package.create!({
            name:                    "httparty",
            package_manager:         :rubygems,
            github_repository_id:    1337,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
          })
          create_corresponding_manifest_for_package(package_with_manifest)

          matching_package = results(repository_ids: 1337, debug: true)
                               .find { |item| item.name == package_with_manifest.name }

          expect(matching_package.debug_should_be_associated_to_repo)
            .to eq true
          expect(matching_package.debug_association_explanation)
            .to be_nil
        end

        it "includes debug info about package+repo association when package has missing manifest association in repo" do
          package_with_manifest = Package.create!({
            name:                    "httparty",
            package_manager:         :rubygems,
            github_repository_id:    1337,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
          })

          matching_package = results(repository_ids: 1337, debug: true)
                               .find { |item| item.name == package_with_manifest.name }

          expect(matching_package.debug_should_be_associated_to_repo)
            .to eq false
          expect(matching_package.debug_association_explanation)
            .to include("manifest could not be found")
        end

        it "includes debug info about package+repo association when package has too low of certainty" do
          package_with_manifest = Package.create!({
            name:                    "httparty",
            package_manager:         :rubygems,
            github_repository_id:    1337,
            repository_id_certainty: PackageToRepoMapping::Certainty::NULL,
          })
          create_corresponding_manifest_for_package(package_with_manifest)

          matching_package = results(repository_ids: 1337, debug: true)
                               .find { |item| item.name == package_with_manifest.name }

          expect(matching_package.debug_should_be_associated_to_repo)
            .to eq false
          expect(matching_package.debug_association_explanation)
            .to include("Certainty of match did not meet the minimum")
        end

        it "includes packages without corresponding manifests with a mapping override" do
          included = Package.create!({
            name:                    "fake-rails",
            package_manager:         :rubygems,
            github_repository_id:    15,
            repository_id_certainty: PackageToRepoMapping::Certainty::OVERRIDE
          })

          expect(results(repository_ids: 15))
            .to eq [included]
        end

        it "returns packages in alpha order" do
          package_1 = Package.create!({
            name:                    "rake",
            package_manager:         :rubygems,
            github_repository_id:    2,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST
          })
          create_corresponding_manifest_for_package(package_1)

          package_2 = Package.create!({
            name:                    "httparty",
            package_manager:         :rubygems,
            github_repository_id:    1,
            repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST
          })
          create_corresponding_manifest_for_package(package_2)

          expect(results(repository_ids: [1, 2]))
            .to match_array [package_2, package_1]
        end

        it "returns packages whose name matches the repo exactly first" do
          Repository.create!(github_repository_id: 8514, nwo: "rails/rails")

          %w(rails railties activesupport actioncable activemodel).shuffle.each do |package_name|
            package = Package.create!({
              name:                    package_name,
              package_manager:         :rubygems,
              github_repository_id:    8514,
              repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
            })
            create_corresponding_manifest_for_package(package)
          end

          result_names = results(repository_ids: [8514]).collect(&:name)

          # We'd like our order to be Rails first, followed by the rest of the packages alphabetically.
          # RSpec doesn't match Arrays based on order, so we've got to do this. :|
          expect(result_names.first).to eq("rails")
          expect(result_names.second).to eq("actioncable")
          expect(result_names.third).to eq("activemodel")
          expect(result_names.fourth).to eq("activesupport")
          expect(result_names.fifth).to eq("railties")
        end

        it "doesn't n+1 on repository" do
          Repository.create!(github_repository_id: 8514, nwo: "rails/rails")

          %w(rails railties activesupport actioncable activemodel).shuffle.each do |package_name|
            package = Package.create!({
              name:                    package_name,
              package_manager:         :rubygems,
              github_repository_id:    8514,
              repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
            })
            create_corresponding_manifest_for_package(package)
          end

          expect {
            results(repository_ids: [8514]).collect(&:name)
          }.to make_database_queries(count: 1)
        end
      end

      def create_corresponding_manifest_for_package(package)
        repository = Repository.where({
          github_repository_id: package.github_repository_id
        }).first_or_create!

        Manifest.create!({
          repository:      repository,
          manifest_type:   :gemspec,
          name:            package.name,
          package_manager: package.package_manager || :rubygems,
          latest_git_ref:  "abc",
          last_pushed_at:  Time.now,
        })
      end

      def results(options = {})
        described_class.new(options.with_indifferent_access).results
      end
    end
  end
end
