require "rails_helper"

describe "querying for unmapped packages" do
    before do
        factory do
        given_package("httparty", "1.0.0")
          .update_package({
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL,
              package_manager: 1,
              repository_id: nil
        })

        given_package("lodash", "1.2.0")
          .update_package({
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL,
              package_manager: 3,
              repository_id: nil
        })

        given_package("lodash", "1.0.0")
          .update_package({
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL,
              package_manager: 2,
              repository_id: nil
        })

        given_package("express", "1.0.0")
          .update_package({
              repository_id_certainty: PackageToRepoMapping::Certainty::NULL,
              package_manager: 2,
              repository_id: nil
        })
        end
    end

    it "finds unmapped packages by name" do
        query <<-QUERY.strip_heredoc
          {
            unmappedPackages(names: ["httparty"]) {
              edges {
                node {
                  name
                  packageManager
                }
              }
            }
          }
        QUERY

        expect(results).to eq({
          unmappedPackages: {
            edges: [
              {
                node: {
                  name: "httparty",
                  packageManager: "RUBYGEMS"
                }
              }
            ]
          }
        })
    end

    it "finds unmapped packages by package manager" do
        query <<-QUERY.strip_heredoc
          {
            unmappedPackages(packageManager: NPM) {
              edges {
                node {
                  name
                  packageManager
                }
              }
            }
          }
        QUERY

        package_names = results[:unmappedPackages][:edges].map { |edge| edge[:node][:name] }


        expect(package_names).to match_array(["lodash", "express"])
    end

    it "finds unmapped packages by package manager and package name" do
        query <<-QUERY.strip_heredoc
          {
            unmappedPackages(names: ["lodash"], packageManager: NPM) {
              edges {
                node {
                  name
                  packageManager
                }
              }
            }
          }
        QUERY

        expect(results).to eq({
          unmappedPackages: {
            edges: [
              {
                node: {
                  name: "lodash",
                  packageManager: "NPM"
                },
              }
            ]
          }
        })
    end

    it "limits results of unmapped packages" do
      query <<-QUERY.strip_heredoc
        {
          unmappedPackages(packageManager: NPM, limit: 1) {
            edges {
              node {
                name
                packageManager
              }
            }
          }
        }
      QUERY

      expect(results[:unmappedPackages][:edges].length).to eq 1
    end
end
