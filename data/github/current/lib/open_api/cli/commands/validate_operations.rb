# typed: true
# frozen_string_literal: true

module OpenApi
  module CLI
    module Commands
      class ValidateOperations
        def self.validate(cleanup_orphaned: false)
          GitHub.openapi_release = GitHub.default_openapi_release

          operations_glob = File.join(Rails.root, "app", "api", "description", "operations", "**", "*.yaml")

          paths = Dir[operations_glob]

          operations = paths.map { |path| OpenApi::Description::Operation.from_path(path, webhook: false) }

          operations_with_handlers = []
          operations_without_source_or_releases = []
          deprecated_operations_without_source_or_releases = []

          operations.each do |operation|
            if operation.releases.empty?
              matches = GitHub::Grep.new.code_use(
                /(operation_id:\s*"#{operation.id}"|operation_ids:\s*\[.*"#{operation.id}".*\])/,
                dirs: %w[app/api]
              )

              deprecated = operation.deprecated?

              if matches.empty? && deprecated
                deprecated_operations_without_source_or_releases << operation
              elsif matches.empty? && !deprecated
                operations_without_source_or_releases << operation
              else
                operations_with_handlers << operation
              end
            end
          end

          if cleanup_orphaned
            puts "Cleaning up orphaned operations..."
            puts

            serviceowners_path = File.join(Rails.root, "SERVICEOWNERS")

            serviceowners_before = File.read(serviceowners_path)
            current_serviceowners = serviceowners_before.dup

            deprecated_operations_without_source_or_releases.each do |o|
              File.delete(o.source_path)
              operation_path = Pathname.new(o.source_path).relative_path_from(Rails.root).to_s
              puts " - Removing #{operation_path}..."

              serviceowners_text = File.read(serviceowners_path)
              path_regex = /#{operation_path}\s+:.*\n/
              current_serviceowners = current_serviceowners.gsub(path_regex, "")
            end

            puts

            if current_serviceowners != serviceowners_before
              puts "Regenerating service files as operations had SERVICEOWNERS entries..."
              puts
              File.write(serviceowners_path, current_serviceowners)
              `bin/generate-service-files.rb`
            end
          elsif deprecated_operations_without_source_or_releases.any?
            puts "WARNING: These operations are marked as deprecated, do not belong to any releases, and have no API handler in the repository:\n\n"

            deprecated_operations_without_source_or_releases.each { |o| puts(" - #{o.id}") }

            puts
            puts "Re-run this command with `--cleanup-orphaned` attached to remove these from the repository."
            puts
          end

          if operations_with_handlers.any?
            puts "WARNING: These operations do not belong to any releases, but an API handler exists for this operation in the repository:\n\n"

            operations_with_handlers.each { |o| puts(" - #{o.id}#{(o.published? ? " (published) " : "")}") }

            puts
            puts "Review these handlers to resolve this issue."
            puts "If the handler should be listed in a release, update the operation file to include a release."
            puts "If a different published release should be used, update the handler to use this operation and mark the other operation as `deprecated: true`"
            puts
          end

          if operations_without_source_or_releases.any?
            puts "WARNING: These operations do not belong to any releases, and have no API handler currently:\n\n"

            operations_without_source_or_releases.each { |o| puts(" - #{o.id}") }

            puts
            puts "These should be set to `deprecated: true` and deployed to mark the operations as officially deprecated."
            puts
          end

          false
        end
      end
    end
  end
end
