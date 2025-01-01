# typed: true
# frozen_string_literal: true

require "open_api/description/overlay"

module OpenApi
  module CLI
    module Commands
      # Patch files. Only supports MergingPatch patches currently.
      class Patch < Command
        def run(targets)
          raw_patch = $stdin.read
          yaml_patch = YAML.safe_load(raw_patch)
          patch = OpenApi::Description::MergingPatch.new(yaml_patch)
          say "Applying patch:"
          say "---", :yellow
          say raw_patch, :yellow
          targets.each do |target|
            content = YAML.load_file(target)
            patch.apply(content)
            File.open(target, "w") do |f|
              f.puts YAML.dump(content)
            end
            prefix "#{target}: "
            say "✔️", :green
          end
        end
      end
    end
  end
end
