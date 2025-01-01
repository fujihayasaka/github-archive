require "dependency_graph/sbom/spdx/spdx_package"

module DependencyGraph
  module SBOM
    module SPDX
      class SPDXDocument
        attr_reader :name, :namespace, :packages

        def initialize(name:, namespace:, packages:, additional_tools:, document_package_download_location:, document_package_license_declared:, document_package_purl:)
          @name = name
          @namespace = namespace
          @packages = packages
          @additional_tools = additional_tools
          @document_package_download_location = document_package_download_location
          @document_package_license_declared = document_package_license_declared
          @document_package_purl = document_package_purl
        end

        def self.from_repository(repository_name:, repository_license:, namespace_base:, packages:, additional_tools: [])
          uuid = SecureRandom.hex(8)
          # https://apidock.com/ruby/URI/join/class#1245-Be-careful-with-path-vs-endpoint
          namespace = URI::join(namespace_base, "#{repository_name}/", "dependency_graph/", "sbom-#{uuid}").to_s

          reverse_host = URI.parse(namespace_base).hostname.split(".").reverse.join(".")
          name = "#{reverse_host}.#{repository_name}"

          SPDXDocument.new(
            name: name,
            namespace: namespace,
            packages: packages,
            additional_tools: additional_tools,
            document_package_download_location: "git+" + URI::join(namespace_base, repository_name).to_s,
            document_package_license_declared: repository_license,
            document_package_purl:
              if URI.parse(namespace_base).hostname == "github.com"
                "pkg:github/#{repository_name}"
              end,
          )
        end

        def generate
          generated_time = Time.now.utc.iso8601
          creators = [
            "Tool: GitHub.com-Dependency-Graph",
            *@additional_tools
          ]

          creator_comment =
            if @packages.any? { |pack| pack.exact_version.nil? }
              "Exact versions could not be resolved for some packages. For more information: https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-the-dependency-graph#dependencies-included."
            end

          document_package_spdx = generate_document_package
          packages_spdx = @packages.map(&:generate)

          {
            "SPDXID": "SPDXRef-DOCUMENT",
            "spdxVersion": "SPDX-2.3",
            "creationInfo": {
              "created": generated_time,
              "creators": creators,
              "comment": creator_comment
            }.compact,
            "name": @name,
            "dataLicense": "CC0-1.0",
            "documentDescribes": [document_package_spdx[:SPDXID]],
            "documentNamespace": @namespace,
            "packages": [document_package_spdx] + packages_spdx,
            "relationships":
              packages_spdx.map do |package_spdx|
                {
                  relationshipType: "DEPENDS_ON",
                  spdxElementId: document_package_spdx[:SPDXID],
                  relatedSpdxElement: package_spdx[:SPDXID]
                }
              end
          }.compact
        end

        def generate_document_package
          {
            "SPDXID": "SPDXRef-#{SPDXPackage.generate_legal_spdx_id(@name)}",
            "name": "#{@name}",
            "versionInfo": "",
            "downloadLocation": @document_package_download_location.presence || "NOASSERTION",
            "licenseDeclared": document_package_license_declared,
            "filesAnalyzed": false,
            "supplier": "NOASSERTION",
            "externalRefs":
              if @document_package_purl.present?
                [{
                  "referenceCategory": "PACKAGE-MANAGER",
                  "referenceType": "purl",
                  "referenceLocator": @document_package_purl
                }]
              end
            }.compact
        end

        private
        def document_package_license_declared
          return if @document_package_license_declared.nil? || @document_package_license_declared == "NOASSERTION"
          @document_package_license_declared if Spdx.valid? @document_package_license_declared
        end
      end
    end
  end
end
