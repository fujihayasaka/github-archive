# frozen_string_literal: true

module ManifestAdapters
  module Maven
    module Parsers
      # Parses a string containing a pom.xml file
      class PomXml < ManifestAdapters::Parsers::Base
        def initialize(content)
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
          @xml_exception || @xml.errors.present? || group_id.blank? || artifact_id.blank?
        end

        def name
          # We use ':' as the separator between groupid and artifactid, following the convention in Gradle
          "#{group_id}:#{artifact_id}"
        end

        def version
          (@xml.at_css("project>version") || @xml.at_css("project>parent>version"))&.text
        end

        def dependencies
          dependencies = @xml.css("dependencies>dependency")
          plugins = @xml.css("plugins>plugin")

          @dependencies ||= [dependencies, plugins].map do |xml_nodes|
            xml_nodes.map do |elem|
              grp_id = properties[elem.at_css("groupId")&.text]
              art_id = properties[elem.at_css("artifactId")&.text]
              package_name = "#{grp_id}:#{art_id}"

              raw_scope = elem.at_css("scope")&.text
              resolved_scope = ManifestAdapters::Maven.parse_scope(raw_scope)

              raw_version = properties[elem.at_css("version")&.text].to_s
              resolved_version = ManifestAdapters::Maven::Requirements.parse(raw_version)

              # TODO: malformed decision should be based on version and scope resolution too!
              is_malformed = grp_id.nil? || art_id.nil?

              ManifestAdapters::Manifest::Dependency.new(
                package_name: package_name,
                requirements: resolved_version,
                raw_requirements: raw_version,
                scope:        resolved_scope,
                malformed:    is_malformed,
              )
            end
          end.flatten
        end

        private

        def group_id
          # If we don't have a groupId in the project, check the parent
          properties[@xml.at_css("project>groupId")&.text || @xml.at_css("project>parent>groupId")&.text]
        end

        def artifact_id
          properties[@xml.at_css("project>artifactId")&.text || @xml.at_css("project>parent>artifactId")&.text]
        end

        def properties
          # This is the hash of properties that's used to store "variables" in XML
          @properties ||= Properties.new(@xml.at_css("project properties")&.children, version: version)
        end

        class Properties
          PROPERTY_REGEX = /\$\{(?<property>[^\}]*)\}/
          GA_LABEL_REGEX = /[\.-]RELEASE$/
          def initialize(properties, version: nil)
            @properties = properties&.map do |elem|
              [elem.name, elem.text]
            end.to_h

            # Manifest dependencies can commonly call on the project's parent version for their version
            @properties["project.version"] = version unless @properties["project.version"]
          end

          def [](str)
            # Sometimes strings look like "${some_library.version}".
            # We need to look them up from the properties hash.
            if str && (matches = str.scan(PROPERTY_REGEX).flatten).present?
              output = str
              matches.each do |match|
                if @properties[match]
                  output = output.gsub("${#{match}}", @properties[match])
                else
                  unless match.start_with?("env.", "settings.")
                    # Let's invalidate entire value if there's some invalid property.
                    # We'll avoid creating junk versions, etc.
                    return @properties[match]
                  else
                    # Manifests can have properties like `env.something` and `settings.something`
                    # These aren't defined in the manifest itself so we can't get the information
                    # Let's just return a blank string.
                    output = output.gsub("${#{match}}", "")
                  end
                end
              end

              output
            elsif str && str.match(GA_LABEL_REGEX)
              str.gsub(GA_LABEL_REGEX, "")
            else
              str
            end
          end
        end
      end
    end
  end
end
