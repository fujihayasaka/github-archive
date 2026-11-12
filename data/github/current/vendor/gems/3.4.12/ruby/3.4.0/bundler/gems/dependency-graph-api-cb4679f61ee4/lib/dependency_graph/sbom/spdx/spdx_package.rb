module DependencyGraph
  module SBOM
    module SPDX
      class SPDXPackage
        ILLEGAL_SPDX_ID_CHARACTERS = Regexp.compile(/[^a-zA-Z0-9\-.]+/)
        VALID_LICENSES_CACHE = Set.new

        attr_reader :dependency

        def initialize(dependency:)
          @dependency = dependency
        end

        def self.generate_legal_spdx_id(name)
          # Only alphanumeric characters, dashes, and periods are allowed in SPDX IDs
          if name =~ ILLEGAL_SPDX_ID_CHARACTERS
            legal_name = name.gsub("@", "")
            legal_name = legal_name.gsub(ILLEGAL_SPDX_ID_CHARACTERS, "-")
          end
          legal_name ? legal_name : name
        end

        def purl
          return @purl if defined?(@purl)

          purl_type = package_manager.purl_type
          namespace, package_name = PackageUrls::PackageUrl.parse_package_name(purl_type, name)

          @purl = PackageUrls::PackageUrl.new(
            type: purl_type,
            namespace: namespace,
            name: package_name,
            version: exact_version || nil,
          ).to_purl
        end

        def package_manager
          dependency.package_manager
        end

        def name
          dependency.package_name
        end

        def exact_version
          dependency.exact_version
        end

        def version_range
          dependency.requirement_set.serialize
        end

        def spdx_id
          base_id = "SPDXRef-#{package_manager}-#{SPDXPackage.generate_legal_spdx_id(name)}"
          # Even "exact" versions can include things like 4.*.* (in actions) which is not a valid SPDX ID
          base_id = "#{base_id}-#{SPDXPackage.generate_legal_spdx_id(exact_version)}" if exact_version
          base_id
        end

        def generate
          externalRefs = [
            {
              "referenceCategory": "PACKAGE-MANAGER",
              "referenceLocator": purl,
              "referenceType": "purl",
             }
          ]

          attributions = dependency.attributions&.join(", ") if dependency.attributions&.any?

          {
            "SPDXID": spdx_id,
            "name": "#{package_manager}:#{name}",
            "versionInfo": exact_version || version_range,
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": false,
            "licenseConcluded": license_concluded,
            "supplier": "NOASSERTION",
            "externalRefs": externalRefs,
            "copyrightText": attributions,
          }.compact
        end

        private
        def license_concluded
          license = dependency.license
          return if license.nil? || license == "NOASSERTION"

          return license if VALID_LICENSES_CACHE.include?(license)

          if Spdx.valid?(license)
            VALID_LICENSES_CACHE.add(license)
            return license
          end
        end
      end
    end
  end
end
