require "rails_helper"

describe ExperimentalService::V1::Handler do
  let(:handler) { ExperimentalService::V1::Handler.new }

  describe "get_releases_for_package" do
    it "returns releases for a package" do
      factory do
        given_package("react", "1.0.0", :npm)
        given_package("react", "2.0.0", :npm)
        given_package("react", "3.0.0-alpha", :npm)
        # Throw in a package with the same name but a different ecosystem to make sure
        # we are properly filtering on ecosystem!
        given_package("react", "1.2.3", :rubygems)
      end

      req = DependencyGraphAPI::V1::GetReleasesForPackageRequest.new({
        package_manager: :PACKAGE_MANAGER_NPM,
        package_name: "react"
      })

      resp = handler.get_releases_for_package(req, {})

      expect(resp.to_h).to eq({
        package_releases: [
          { version: "1.0.0" },
          { version: "2.0.0" },
          { version: "3.0.0-alpha" }
        ]
      })
    end

    it "returns an empty array for non-existent package" do
      req = DependencyGraphAPI::V1::GetReleasesForPackageRequest.new({
        package_manager: :PACKAGE_MANAGER_NPM,
        package_name: "jquery"
      })

      resp = handler.get_releases_for_package(req, {})

      expect(resp.to_h).to eq({
        package_releases: []
      })
    end
  end
end
