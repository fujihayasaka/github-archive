# typed: true
# frozen_string_literal: true

require "thor"
require "erb"
require_relative "../../../../app/api/versioning"

module OpenApi
  module CLI
    module Commands
      class Changeset < Thor
        desc "list", "List openapi active changesets by API version"
        method_option :output, aliases: "-o", desc: "Output directory"
        def list
          schedule = OpenApi::Description::Changeset.schedule.fetch.map do |version, changesets|
            changesets = changesets.map do |changeset|
              { "name" => changeset[1].name, "description" => changeset[1].description, "releases" => changeset[1].releases }
            end
            { version => changesets }
          end

          raise ArgumentError, "Must specify an output directory when using --output." if options[:output] == "output"

          if options.output?
            File.write(OpenApi.root.join(options.output, "active-changesets.yaml"), YAML.dump(schedule))
          else
            $stdout.puts "#{YAML.dump(schedule)}"
          end
        end

        desc "info", "Retrieve changeset information by name"
        def info(changeset_name)
          changeset_file = OpenApi::Description::Changeset.find_path(changeset_name)

          raise ArgumentError, "Changeset #{changeset_name} not found." unless changeset_file

          changeset = YAML.safe_load(File.read(changeset_file))
          changeset["files_containing_breaking_changes"] = OpenApi::Description::BreakingChanges.find(changeset_name)

          $stdout.puts YAML.dump(changeset)
        end
      end
    end
  end
end
