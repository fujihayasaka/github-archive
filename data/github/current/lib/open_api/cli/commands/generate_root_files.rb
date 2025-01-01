# typed: true
# frozen_string_literal: true

require_relative "./operation_owners"

module OpenApi
  module CLI
    module Commands
      class GenerateRootFiles < Command

        def run(release_identifiers = [])
          diffs_added = Hash.new { |h, k| h[k] = [] }
          diffs_removed = Hash.new { |h, k| h[k] = [] }

          releases = OpenApi::Description::Release.find_all(release_identifiers, include_unpublished: true)

          releases.delete_if { |release| release.identifier == GitHub.enterprise_test_openapi_release }

          releases.each do |release|
            release_path = OpenApi.root.join("#{release.identifier}.yaml")
            next if !File.exist?(release_path)

            current_release = YAML.safe_load(ERB.new(File.read(release_path)).result)

            new_operations = operations(release.content)
            old_operations = operations(current_release)

            new_webhooks = webhooks(release.content)
            old_webhooks = webhooks(current_release)

            path_diff_added       = new_operations - old_operations
            path_diff_removed     = old_operations - new_operations
            webhooks_diff_added   = new_webhooks - old_webhooks
            webhooks_diff_removed = old_webhooks - new_webhooks

            (path_diff_added | webhooks_diff_added).each do |d|
              diffs_added[d] << release.identifier
            end

            (path_diff_removed | webhooks_diff_removed).each do |d|
              diffs_removed[d] << release.identifier
            end
          end

          if diffs_removed.any?
            $stderr.puts "The following operations were removed from the description."
            diffs_removed.each do |diff, releases|
              say "#{diff} in #{releases.uniq.join(", ")}", :red
            end

            cont = yes? "Continue?(y/n)"

            if !cont
              $stderr.puts "Aborting. Rerun this command once you've made the modifications."
              exit(1)
            end
          end

          if diffs_added.any?
            $stderr.puts "The following operations were added to the description."
            $stderr.puts "Use the `published: false` option under x-github-internal to avoid releasing these operations."

            diffs_added.each do |diff, releases|
              say "#{diff} in #{releases.uniq.join(", ")}", :green
            end

            cont = yes? "Continue?(y/n)"

            if !cont
              $stderr.puts "Aborting. Rerun this command once you've made the modifications."
              exit(1)
            end
          end

          releases.each do |release|
            path, wrote_bytes = release.write(format: :unbundled, base_path: OpenApi.root)
            say "✅  Wrote #{wrote_bytes} bytes to #{path}"
          end

          operation_owners_file = OpenApi.root.join("operation-owners.yaml")
          operations_owner_payload = OpenApi::CLI::Operations::get_operation_owners_payload(releases)
          operation_owners_yaml = YAML.dump(operations_owner_payload)
          wrote_bytes = File.write(operation_owners_file, operation_owners_yaml)
          say "✅  Wrote #{wrote_bytes} bytes to operation owners cache"

          say "🎉 Root files updated! Please commit the resulting files.", :green
        end

        private

        def operations(openapi)
          openapi["paths"].flat_map do |path, operation|
            operation.map do |method, op|
              begin
                internal_metadata = YAML.safe_load(File.read(OpenApi.root.join(op["$ref"])))["x-github-internal"]
              rescue Errno::ENOENT
                next "REMOVED OPERATION: #{method.upcase} #{path}"
              end

              if internal_metadata.dig("published")
                "ADDED PUBLISHED OPERATION:   #{method.upcase} #{path}"
              else
                "ADDED UNPUBLISHED OPERATION: #{method.upcase} #{path}"
              end
            end
          end
        end

        def webhooks(openapi)
          webhooks_key = OpenApi.webhook_key(openapi["openapi"])
          # Return if the root file is missing the x-webhooks/webhooks key entirely
          return [] if openapi[webhooks_key].nil?

          openapi[webhooks_key].map do |webhook, operation|
            filepath = operation.dig("post", "$ref")
            begin
              internal_metadata = YAML.safe_load(File.read(OpenApi.root.join(filepath)))["x-github-internal"]
            rescue Errno::ENOENT
              next "REMOVED WEBHOOK: #{webhook}"
            end
            if internal_metadata["published"]
              "ADDED PUBLISHED WEBHOOK: #{webhook}"
            else
              "ADDED UNPUBLISHED WEBHOOK: #{webhook}"
            end
          end
        end

      end
    end
  end
end
