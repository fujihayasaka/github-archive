require "rails_helper"

module Queries
    describe PackageQuery do
        describe "#unmapped_packages" do
          it "returns unmapped packages for a given package name" do
            package = Package.create!({
              name: "bootstrap",
              package_manager: :npm,
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL
            })

            package_2 = Package.create!({
              name: "bootstrap",
              package_manager: :nuget,
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL
            })

            expect(results(name: package.name)).to match_array [package, package_2]
          end

          it "returns unmapped packages for a given package manager" do
            package = Package.create!({
              name: "JUnit",
              package_manager: :maven,
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL
            })

            package_2 = Package.create!({
              name: "Guava",
              package_manager: :maven,
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL
            })

            expect(results(package_manager: package.package_manager)).to match_array [package, package_2]
          end

          it "returns unmapped packages for given package manager and package name" do
            package = Package.create!({
              name: "httparty",
              package_manager: :rubygems,
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL
            })

            expect(results(name: package.name, package_manager: package.package_manager)).to match_array [package]
          end

          def results(options = {})
            described_class.new(options).unmapped_packages
          end
        end
    end
end
