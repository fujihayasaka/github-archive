require "rails_helper"

describe PackageDependency do
  describe ".package_label" do

    let(:package_release) do
      factory.given_package("numpy", "1.20.3", :pip)
      get_package_release("numpy", "1.20.3")
    end
    it "uses packageName as packageLabel if packageLabel is not set" do
      dependency = factory.given_dependency({
        package_name: "beautifulsoup4",
        requirements: "= 4.0",
        dependent: package_release
        })

      expect(dependency.package_label).to eq("beautifulsoup4")
    end

    it "returns the correct packageLabel if packageLabel is set" do
      dependency = factory.given_dependency({
        package_name: "beautifulsoup4",
        package_label: "BeautifulSoup 4",
        requirements: "= 4.0",
        dependent: package_release
      })

      expect(dependency.package_label).to eq("BeautifulSoup 4")
    end
  end
end
