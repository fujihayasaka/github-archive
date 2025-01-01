# typed: true
# frozen_string_literal: true

require "thor"
require "pathname"

module OpenApi
  module CLI
    module Commands
      class Overlays < Thor
        method_option :dry_run, aliases: "-d", type: :boolean, default: false
        desc "convert-to-modify <path/to/file.yaml> <ghes-version>", "Convert x-githubEnterpriseOverlays to x-github-modify properties in file, targeting the provided GHES version"
        def convert_to_modify(path, ghes_version)
          release = OpenApi::Description::Release.new("ghes", ghes_version)
          doc = YAML.load_file(path)

          overlay = OpenApi::Description::Overlay.find_all(doc, type: [OpenApi::Description::Overlay::LEGACY_KEY]).find do |o|
            o.match?(release)
          end

          if overlay
            doc[OpenApi::Description::Overlay::MODIFY_KEY] = { "ghes" => overlay.patch.data }
          end

          doc.delete(OpenApi::Description::Overlay::LEGACY_KEY)

          if options[:dry_run]
            puts YAML.dump(doc)
          elsif YAML.dump(YAML.load_file(path)) != YAML.dump(doc)
            File.open(path, "w") do |f|
              f.puts YAML.dump(doc)
            end
          end
        end
      end
    end
  end
end
