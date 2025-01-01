module ManifestAdapters
  module Nuget
    module Parsers
      # Parses a string containing a nuspec file
      class Nuspec < ManifestAdapters::Parsers::Base
        def initialize(content)
          @xml_empty = content.blank?
          @xml_exception = false
          @xml =
            begin
              Nokogiri::XML(content) do |conf|
                conf.noblanks.nonet.nodtdload
              end
            rescue Nokogiri::XML::SyntaxError
              @xml_exception = true
              Nokogiri::XML("")
            end
        end

        def malformed?
          @xml_exception || @xml.errors.present? || @xml_empty || name.blank? || version.blank?
        end

        def name
          @xml.css("id")&.text
        end

        def version
          @xml.css("version")&.text
        end

        def dependencies
          dependencies = @xml.css("dependencies dependency")

          dependencies.map do |dependency|
            resolved_reqs = ManifestAdapters::Nuget::Requirements.parse(dependency["version"])
            resolved_scope = ManifestAdapters::Nuget.parse_include(dependency["include"])
            # TODO: malformed decision should take resolved scope and version into account!
            is_malformed = dependency["id"].blank? || dependency["version"].blank?

            ManifestAdapters::Manifest::Dependency.new(package_name: dependency["id"],
                                                       requirements: resolved_reqs,
                                                       raw_requirements: dependency["version"],
                                                       scope:        resolved_scope,
                                                       malformed:    is_malformed)
          end
        end
      end
    end
  end
end
