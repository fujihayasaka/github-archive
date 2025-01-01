# frozen_string_literal: true

module ManifestAdapters
  module Nuget
    module Parsers
      # Parses a string containing a nuspec file
      class Project < ManifestAdapters::Parsers::Base
        def initialize(filename, content)
          @filename = filename
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
          @xml_exception || @xml.errors.present? || @xml_empty || (name.blank? && dependencies.blank?)
        end

        def name
          return @name if defined?(@name)

          @name = @xml.css("PropertyGroup PackageId")&.text
          @name = File.basename(@filename, File.extname(@filename)) if @name.empty?
          @name
        end

        def version
          v = @xml.css("PropertyGroup PackageVersion")&.text
          v = @xml.css("PropertyGroup Version")&.text if v.empty?
          v
        end

        # <PackageReference Include="Newtonsoft.Json" Version="9.0.1">
        # </PackageReference>
        def dependencies
          dependencies = @xml.css("ItemGroup PackageReference")
          dependencies.map do |dependency|
            version = if dependency["Version"]
              dependency["Version"]
            elsif dependency.children.css("Version").present?
              dependency.children.css("Version").text
            else
              # If a version range isn't specified, we'd like to default to `>= 0` so that we still
              # display dependencies in the UI and send vulnerability alerts. In order to do this,
              # we need to mimic the Nuget requirements syntax so our parser will set the requirements.
              "[0,)"
            end

            resolved_reqs = ManifestAdapters::Nuget::Requirements.parse(version)
            # TODO: malformed decision should take resolved scope and version into account!
            is_malformed = dependency["Include"].blank?

            ManifestAdapters::Manifest::Dependency.new(package_name: dependency["Include"],
                                                       requirements: resolved_reqs,
                                                       raw_requirements: version,
                                                       scope:        Types::Scope[:runtime],
                                                       malformed:    is_malformed)
          end
        end
      end
    end
  end
end
