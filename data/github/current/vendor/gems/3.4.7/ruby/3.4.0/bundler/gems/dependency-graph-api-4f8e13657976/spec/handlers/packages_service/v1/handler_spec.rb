require "rails_helper"

describe PackagesService::V1::Handler do
  let(:handler) { described_class.new }
  published_at = Time.now
  before do
    factory do
      def add_attributions_to_release(release, attributions)
        a = attributions.map do |attribution|
          Attribution.create!(package_release: release, attribution: attribution)
        end

        release.update!(attributions: a)
      end

      package_factory = given_package("react", "1.0.0", :npm)
      add_attributions_to_release(package_factory.release, ["Copyright 2024 Aguirre, der Zorn Gottes"])
      package_factory.release.update!(license: "MIT", published_at: published_at)

      package_factory = given_package("react", "2.0.0", :npm)
      add_attributions_to_release(package_factory.release, ["1", "2", "3"])

      package_factory = given_package("react", "3.0.0-alpha", :npm)
      package_factory.release.update!(license: "BSD")

      # Throw in a package with the same name but a different ecosystem to make sure
      # we are properly filtering on ecosystem!
      given_package("react", "1.2.3", :rubygems)
    end
  end

  context "get_package_versions" do
    it "returns releases for a package given the ecosystem, name and version spec" do

      req = DependencyGraphAPI::V1::GetPackageVersionsRequest.new({
        package_versions: [{
          package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          package_version: "1.0.0"
        }, {
          package_manager: :PACKAGE_MANAGER_NPM,
          package_name: "react",
          package_version: "2.0.0"
        }],
        include_copyright_attributions: true
      })

      resp = handler.get_package_versions(req, {})

      expect(resp.to_h).to eq({
        package_versions: [
          { package_manager: :PACKAGE_MANAGER_NPM, package_name: "react", attributions: ["Copyright 2024 Aguirre, der Zorn Gottes"], license: "MIT", name: "1.0.0", published_at: { seconds: published_at.to_time.to_i, nanos: 0 }, source_url: "", unpublished_at: nil },
          { package_manager: :PACKAGE_MANAGER_NPM, package_name: "react", attributions: ["1", "2", "3"], license: "", name: "2.0.0", published_at: nil, source_url: "", unpublished_at: nil },
        ]
      })
    end
  end

  context "list_package_versions" do
    it "returns list of versions for a package given the ecosystem and name" do

      req = DependencyGraphAPI::V1::ListPackageVersionsRequest.new({
        package_manager: :PACKAGE_MANAGER_NPM,
        package_name: "react",
        include_licenses: true
      })

      resp = handler.list_package_versions(req, {})

      expect(resp.to_h).to eq({
        package_versions: [
          { package_license: "MIT", package_version: "1.0.0" },
          { package_license: "", package_version: "2.0.0" },
          { package_license: "BSD", package_version: "3.0.0-alpha" },
        ]
      })
    end
  end
end
