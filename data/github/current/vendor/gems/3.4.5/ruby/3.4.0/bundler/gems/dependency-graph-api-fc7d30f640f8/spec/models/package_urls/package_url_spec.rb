require "rails_helper"

describe PackageUrls::PackageUrl do
  # sample test file taken from https://github.com/package-url/packageurl-dotnet/blob/master/tests/TestAssets/test-suite-data.json
  let(:test_data) { JSON.parse(file_fixture("package_urls.json").read, symbolize_names: true) }

  describe "init of package Urls" do
    it "create package_url from canonical string" do
      test_data.each do |entry|
        if entry[:is_invalid] == true
          expect {
            PackageUrls::PackageUrl.from_purl(purl: entry[:purl])
          }.to raise_error(MalformedPackageUrlError)
          next
        end

        purl = PackageUrls::PackageUrl.from_purl(purl: entry[:purl])
        expect(purl.to_purl).to eq(entry[:canonical_purl])
        expect(PackageUrls::PackageUrl::PURL_SCHEME).to eq("pkg")
        expect(purl.type).to eq(entry[:type])
        expect(purl.namespace).to eq(entry[:namespace])
        expect(purl.name).to eq(entry[:name])
        expect(purl.version).to eq(entry[:version])
        expect(purl.sub_path).to eq(entry[:subpath])
        expect(purl.type_dg_api.to_s).to eq(entry[:type_dg_api])
        expect(purl.full_package_name).to eq(entry[:full_package_name])

        if entry[:qualifiers].present?
          expect(purl.qualifiers).not_to be_empty
        end
      end
    end

    it "create package_url from constructor" do
      test_data.each do |entry|
        if entry[:is_invalid] == true
          expect {
            PackageUrls::PackageUrl.new(type: entry[:type],
                                        namespace: entry[:namespace],
                                        name: entry[:name],
                                        version: entry[:version],
                                        qualifiers: entry[:qualifiers],
                                        sub_path: entry[:subpath])
          }.to raise_error(ArgumentError)
          next
        end

        purl = PackageUrls::PackageUrl.new(type: entry[:type],
                                           namespace: entry[:namespace],
                                           name: entry[:name],
                                           version: entry[:version],
                                           qualifiers: entry[:qualifiers],
                                           sub_path: entry[:subpath])

        expect(purl.to_purl).to eq(entry[:canonical_purl])
        expect(purl.type).to eq(entry[:type])
        expect(purl.namespace).to eq(entry[:namespace])
        expect(purl.name).to eq(entry[:name])
        expect(purl.version).to eq(entry[:version])
        expect(purl.sub_path).to eq(entry[:subpath])
        expect(purl.type_dg_api.to_s).to eq(entry[:type_dg_api])
        expect(purl.full_package_name).to eq(entry[:full_package_name])

        if entry[:qualifiers].present?
          expect(purl.qualifiers).not_to be_empty
        end
      end
    end

    it "creates package_url from package release data" do
      # package release with purl type != ecosystem name
      ruby_release = { package_manager: "rubygems", name: "ruby-advisory-db-check", version: "0.12.4" }

      # package releases with namespace
      maven_release = { package_manager: "maven", name: "org.apache.xmlgraphics:batik-anim", version: "1.9.1" }
      npm_release = { package_manager: "npm", name: "@angular/animation", version: "12.3.1" }
      complex_namespace_release = { package_manager: "go", name: "f&o&o/b&a&r/packagename", version: "1.2.3" }

      ruby_purl = "pkg:gem/ruby-advisory-db-check@0.12.4"
      maven_purl = "pkg:maven/org.apache.xmlgraphics/batik-anim@1.9.1"
      npm_purl = "pkg:npm/%40angular/animation@12.3.1"
      complex_namespace_purl = "pkg:golang/f%26o%26o/b%26a%26r/packagename@1.2.3"

      test_packages = [{ purl: ruby_purl, release: ruby_release },
                       { purl: maven_purl, release: maven_release, namespace: "org.apache.xmlgraphics" },
                       { purl: npm_purl, release: npm_release, namespace: "@angular" },
                       { purl: complex_namespace_purl, release: complex_namespace_release, namespace: "f&o&o/b&a&r" }]

      test_packages.each do |package|
        release = package[:release]
        release_purl = described_class.from_package_release(package_manager: release[:package_manager], name: release[:name], version: release[:version])

        expect(release_purl.to_purl).to eq(package[:purl])
        expect(release_purl.namespace).to eq(package[:namespace])
      end
    end
  end
end
