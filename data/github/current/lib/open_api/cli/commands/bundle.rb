# typed: true
# frozen_string_literal: true

module OpenApi
  module CLI
    module Commands
      class Bundle < Command
        class ReleaseApiVersioningConfigNotFound < LoadError; end

        def run(destination, release_identifiers = [], include_deprecated: false, include_unpublished: false, include_api_versions: false, include_next_version: false, include_webhooks: false, generate_dref_json_only: false)
          base_path = Pathname.new(destination)

          all_releases = OpenApi::Description::Release.find_all(release_identifiers, include_unpublished: include_unpublished)
          releases = []

          published, unpublished = all_releases.partition { |release| release.published? }

          deprecated, available = all_releases.partition { |release| release.deprecated? }

          if include_unpublished
            $stderr.puts "- 🚨 Running with `include_unpublished: true`"
            releases = unpublished + published
          else
            releases = published
            unpublished.each do |release|
              $stderr.puts "- ⏩ Skipping #{release.identifier} because it is set as `published: false`. Use `include_unpublished` to bundle anyway."
            end
          end

          if include_deprecated
            $stderr.puts "- 🚨 Running with `include_deprecated: true`"
            releases = releases & (deprecated + available)
          else
            releases = releases & available
            deprecated.each do |release|
              $stderr.puts "- ⏩ Skipping #{release.identifier} because it is set as `deprecated: true`. Use `include_deprecated` to bundle anyway."
            end
          end

          releases.each do |release|
            $stderr.puts "#{release.identifier}:"

            # --api-versioned will process and apply breaking changes to the API versioned files
            if include_api_versions
              # Get API versions from the release's x-github-api-versions extension
              supported_versions = release.api_versions
              # Append the 'next' version to the list if the flag is passed so we generate a fully-applied 'next' description
              if include_next_version && !supported_versions.include?("next")
                supported_versions = supported_versions + ["next"]
              end

              # The general release description includes all supported versions (if any) for that release w/o breaking changes applied (partial)
              $stderr.puts %q(- General Release - All API Versions)
              # Bundled - partial scope
              if !generate_dref_json_only
                path, wrote_bytes = release.write(format: :bundled, serialize_as: :json, base_path: base_path, breaking_changes_scope: :partial, include_next_version: include_next_version, include_webhooks: include_webhooks)
                $stderr.puts "  - ✅ Bundled, JSON (#{(wrote_bytes)}): #{path.expand_path}"
                path, wrote_bytes = release.write(format: :bundled, serialize_as: :yaml, base_path: base_path, breaking_changes_scope: :partial, include_next_version: include_next_version, include_webhooks: include_webhooks)
                $stderr.puts "  - ✅ Bundled, YAML (#{(wrote_bytes)}): #{path.expand_path}"

                # Dereferenced - partial scope
                path, wrote_bytes = release.write(format: :dereferenced, serialize_as: :yaml, base_path: base_path, breaking_changes_scope: :partial, include_next_version: include_next_version, include_webhooks: include_webhooks)
                $stderr.puts "  - ✅ Dereferenced, YAML (#{(wrote_bytes)}): #{path.expand_path}"
              end
              path, wrote_bytes = release.write(format: :dereferenced, serialize_as: :json, base_path: base_path, breaking_changes_scope: :partial, include_next_version: include_next_version, include_webhooks: include_webhooks)
              $stderr.puts "  - ✅ Dereferenced, JSON (#{(wrote_bytes)}): #{path.expand_path}"

              next if supported_versions.nil? || supported_versions.empty?

              # Generate fully applied breaking changes per supported api_version
              supported_versions.each do |api_version|
                # We exclude the `next` versioned schema description by default (internal only) unless the option is passed to include it
                next if api_version == "next" && !include_next_version

                $stderr.puts %Q(- API Version "#{api_version}":)
                # Bundled - full scope
                if !generate_dref_json_only
                  path, wrote_bytes = release.write(format: :bundled, serialize_as: :json, base_path: base_path, breaking_changes_scope: :full, api_version: api_version, include_next_version: include_next_version, include_webhooks: include_webhooks)
                  $stderr.puts "  - ✅ Bundled, JSON (#{(wrote_bytes)}): #{path.expand_path}"
                  path, wrote_bytes = release.write(format: :bundled, serialize_as: :yaml, base_path: base_path, breaking_changes_scope: :full, api_version: api_version, include_next_version: include_next_version, include_webhooks: include_webhooks)

                  $stderr.puts "  - ✅ Bundled, YAML (#{(wrote_bytes)}): #{path.expand_path}"
                  # Dereferenced - full scope
                  path, wrote_bytes = release.write(format: :dereferenced, serialize_as: :yaml, base_path: base_path, breaking_changes_scope: :full, api_version: api_version, include_next_version: include_next_version, include_webhooks: include_webhooks)
                  $stderr.puts "  - ✅ Dereferenced, YAML (#{(wrote_bytes)}): #{path.expand_path}"
                end
                path, wrote_bytes = release.write(format: :dereferenced, serialize_as: :json, base_path: base_path, breaking_changes_scope: :full, api_version: api_version, include_next_version: include_next_version, include_webhooks: include_webhooks)
                $stderr.puts "  - ✅ Dereferenced, JSON (#{(wrote_bytes)}): #{path.expand_path}"
              end
            else
              if !generate_dref_json_only
                # Bundled
                path, wrote_bytes = release.write(format: :bundled, serialize_as: :json, base_path: base_path, include_webhooks: include_webhooks)
                $stderr.puts "- ✅ Bundled, JSON (#{(wrote_bytes)}): #{path.expand_path}"
                path, wrote_bytes = release.write(format: :bundled, serialize_as: :yaml, base_path: base_path, include_webhooks: include_webhooks)
                $stderr.puts "- ✅ Bundled, YAML (#{(wrote_bytes)}): #{path.expand_path}"

                # Dereferenced
                path, wrote_bytes = release.write(format: :dereferenced, serialize_as: :yaml, base_path: base_path, include_webhooks: include_webhooks)
                $stderr.puts "- ✅ Dereferenced, YAML (#{(wrote_bytes)}): #{path.expand_path}"
              end
              path, wrote_bytes = release.write(format: :dereferenced, serialize_as: :json, base_path: base_path, include_webhooks: include_webhooks)
              $stderr.puts "- ✅ Dereferenced, JSON (#{(wrote_bytes)}): #{path.expand_path}"
            end
          end
        end
      end
    end
  end
end
