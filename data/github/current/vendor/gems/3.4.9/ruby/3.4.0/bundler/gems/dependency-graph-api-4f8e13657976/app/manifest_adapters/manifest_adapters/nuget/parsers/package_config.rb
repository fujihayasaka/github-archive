# frozen_string_literal: true

module ManifestAdapters
  module Nuget
    module Parsers
      # Parses a string containing a packages.config file
      class PackageConfig < ManifestAdapters::Parsers::Base
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
          @xml_exception || @xml.errors.present? || @xml_empty
        end

        # packages.config doesn't expose the name of the project, so return nil.
        def name
          nil
        end

        # packages.config doesn't expose the version of the project, so return nil.
        def version
          nil
        end

        def dependencies
          dependencies = @xml.css("packages package")
          dependencies.map do |dependency|
            resolved_version = dependency["allowedVersion"]
            resolved_version = dependency["version"] if resolved_version.to_s.empty?
            resolved_reqs = ManifestAdapters::Nuget::Requirements.parse(resolved_version)
            # TODO: malformed decision should take resolved scope and version into account!
            is_malformed = dependency["id"].blank? || dependency["version"].blank?

            ManifestAdapters::Manifest::Dependency.new(package_name: dependency["id"],
                                                       requirements: resolved_reqs,
                                                       raw_requirements: resolved_version,
                                                       scope:        Types::Scope[:runtime],
                                                       malformed:    is_malformed)
          end
        end
      end
    end
  end
end
