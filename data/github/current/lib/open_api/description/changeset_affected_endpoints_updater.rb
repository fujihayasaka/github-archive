# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    # Synchronizes `affected_endpoints` in changeset YAML files from
    # x-github-breaking-changes annotations.
    class ChangesetAffectedEndpointsUpdater
      ENDPOINTS_COMMENT = "# List of affected endpoints. The value of this field is auto-populated when changesets are promoted to a version."
      READY_TO_SHIP_COMMENT = "# The date on or after which this changeset can be promoted into a fixed version."

      def self.sync(fix: false, changeset_names: nil)
        new.sync(fix: fix, changeset_names: changeset_names)
      end

      def sync(fix: false, changeset_names: nil)
        endpoints_by_changeset = OpenApi::Description::EndpointResolver.resolve_all
        stale_paths = []
        updated_paths = []

        changesets = OpenApi::Description::Changeset.all
        changesets = changesets.select { |cs| changeset_names.include?(cs.name) } if changeset_names

        changesets.each do |changeset|
          file_path = OpenApi.root.join("changesets", changeset.filename)
          content = File.read(file_path)
          expected_endpoints = Array(endpoints_by_changeset[changeset.name]).uniq.sort
          previously_populated = has_populated_endpoints?(content)
          updated_content = update_content(content, expected_endpoints)

          next if updated_content == content

          # Pristine files (empty/absent affected_endpoints) are always auto-updated.
          # Previously populated files are only updated with --fix.
          if previously_populated
            stale_paths << file_path
            if fix
              File.write(file_path, updated_content)
              updated_paths << file_path
            end
          else
            File.write(file_path, updated_content)
            updated_paths << file_path
          end
        end

        {
          stale_paths:,
          updated_paths:,
        }
      end

      private

      # Returns true if the file contains affected_endpoints with actual items,
      # indicating it was previously synced via --fix.
      def has_populated_endpoints?(content)
        content.match?(/(?:\A|\n)affected_endpoints:\s*\n  - \S/)
      end

      def update_content(content, endpoints)
        content_without_existing = remove_existing_affected_endpoints_block(content)

        if endpoints.empty?
          return content if content.match?(/(?:\A|\n)affected_endpoints:\s*\[\]\s*(?:\n|\z)/)
          return content_without_existing
        end

        block = affected_endpoints_block(endpoints)
        insert_before_ready_to_ship(content_without_existing, block)
      end

      def remove_existing_affected_endpoints_block(content)
        lines = content.lines
        filtered_lines = []
        skipping = T.let(false, T::Boolean)

        lines.each do |line|
          if !skipping && line.match?(/\Aaffected_endpoints:\s*(?:\[\])?\s*\z/)
            skipping = true
            next
          end

          if skipping
            if line.start_with?("  - ") || line.strip.empty?
              next
            end
            skipping = false
          end

          filtered_lines << line
        end

        # Remove the nearby explanatory comment too, if present.
        filtered_lines.reject { |line| line.strip == ENDPOINTS_COMMENT }.join
      end

      def affected_endpoints_block(endpoints)
        lines = [ENDPOINTS_COMMENT, "affected_endpoints:"]
        endpoints.each { |endpoint| lines << "  - #{endpoint}" }
        lines.join("\n") + "\n\n"
      end

      def insert_before_ready_to_ship(content, block)
        lines = content.lines
        insertion_index = lines.index { |line| line.strip == READY_TO_SHIP_COMMENT }
        insertion_index ||= lines.index { |line| line.match?(/\A#?\s*ready_to_ship_on_or_after:/) }
        return block + content if insertion_index.nil?

        lines.insert(insertion_index, block)
        lines.join
      end
    end
  end
end
