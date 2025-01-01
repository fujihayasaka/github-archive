# typed: true
# frozen_string_literal: true

require "psych/comments"

module OpenApi
  module CLI
    module Commands
      class Format < OpenApi::CLI::Commands::Command
        def run(args)
          full = args["full"] || false

          paths = []

          operations_glob = File.join(Rails.root, "app", "api", "description", "operations", "**", "*.yaml")
          schemas_glob = File.join(Rails.root, "app", "api", "description", "schemas", "**", "*.yaml")
          webhooks_glob = File.join(Rails.root, "app", "api", "description", "webhooks", "**", "*.yaml")

          paths += Dir[operations_glob]
          # paths += Dir[schemas_glob]
          # paths += Dir[webhooks_glob]

          paths.each do |path|
            if full
              format_file(path)
            else
              remove_double_empty_lines(path)
            end
          end
        end

        def remove_double_empty_lines(full_path)
          text = File.read(full_path)

          new_text = text
            .gsub(/enabledForGitHubApps\: true\n\n/, "enabledForGitHubApps: true\n")
            .gsub(/\n\nx-github-releases:/, "\nx-github-releases:")
            .gsub(/\n\nx-github-resource-owner:/, "\nx-github-resource-owner:")
            .gsub(/\n\nexternalDocs:/, "\nexternalDocs:")
            .gsub(/\n\nx-github-internal:/, "\nx-github-internal:")
            .gsub(/\n\nparameters:/, "\nparameters:")
            .gsub(/\n\nresponses:/, "\nresponses:")
            .gsub(/\n\nx-github:/, "\nx-github:")
            .gsub(/\n\n  category:/, "\n  category:")
            .gsub(/\n\nrequestBody:/, "\nrequestBody:")
            .gsub(/\n\nx-github-overlays:/, "\nx-github-overlays:")
            .gsub(/\n\nx-githubEnterpriseOverlays:/, "\nx-githubEnterpriseOverlays:")

          File.open(full_path, "w") { |file| file.write(new_text) }
        end

        def format_file(full_path)
          doc = Psych::Comments.parse_file(full_path)

          stream = Psych::Nodes::Stream.new
          stream.children << doc

          stream.grep(Psych::Nodes::Mapping).each do |node|
            node.children.each_slice(2) do |k, v|
              if k.value == "$ref"
                k.plain  = true
                k.quoted = false
                k.style = Psych::Nodes::Scalar::ANY
              elsif k.value == "description" && v.is_a?(Psych::Nodes::Scalar)
                if v.value =~ /\n/
                  # description strings with newlines should be formatted to preserve them
                  v.quoted = true
                  v.style  = Psych::Nodes::Scalar::LITERAL
                elsif v.value.length > 120
                  # long description fields should be folded to avoid very long lines in editor
                  v.quoted = true
                  v.style  = Psych::Nodes::Scalar::FOLDED
                end
              end
            end
          end

          File.open(full_path, "w") { |file| file.write(Psych::Comments.emit_yaml(stream)) }
        end
      end
    end
  end
end
