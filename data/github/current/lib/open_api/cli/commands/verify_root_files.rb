# typed: true
# frozen_string_literal: true

require_relative "./operation_owners"
require "pathname"
require "tmpdir"

module OpenApi
  module CLI
    module Commands
      class VerifyRootFiles < Command
        def run(release_identifiers = [])
          releases = OpenApi::Description::Release.find_all(release_identifiers, include_unpublished: true)

          releases.delete_if { |release| release.identifier == GitHub.enterprise_test_openapi_release }

          success = T.let(true, T::Boolean)

          changeset_verification = OpenApi::Description::ReleasedChangesetEditsVerifier.new.verify
          if changeset_verification.valid?
            $stderr.puts "✅ Released changeset edits are valid"
          else
            $stderr.puts "❌ Released changeset edits are invalid"
            changeset_verification.violations.each do |violation|
              $stderr.puts "   - #{violation}"
            end
            success = false
          end

          releases.each do |release|
            current_release = YAML.safe_load(ERB.new(File.read(OpenApi.root.join("#{release.identifier}.yaml"))).result)

            if release.content == current_release
              $stderr.puts "✅ Release #{release.identifier} is up to date"
            else
              $stderr.puts "❌ Release #{release.identifier} should be regenerated"
              success = false
            end
          end

          current_contents = File.read(OpenApi.root.join("operation-owners.yaml"))
          operations_owner_payload = OpenApi::CLI::Operations::get_operation_owners_payload(releases)
          operation_owners_yaml = YAML.dump(operations_owner_payload)

          if current_contents == operation_owners_yaml
            $stderr.puts "✅ Operation owners cache is up to date"
          else
            $stderr.puts "❌ Operation owners cache should be regenerated"
            success = false
          end

          success = verify_changelogs(releases, success)

          success
        end

        private

        def verify_changelogs(releases, success)
          release_identifiers = changelog_release_identifiers(releases)
          return success if release_identifiers.empty?

          Dir.mktmpdir do |dir|
            generated_paths = OpenApi::Description::ChangelogGenerator.generate_all(
              output_dir: dir,
              release_identifiers: release_identifiers,
              include_unpublished_releases: false,
            )

            release_identifiers.each do |release_identifier|
              current_path = OpenApi.root.join("changelogs", release_identifier, "CHANGELOG.md")
              generated_path = Pathname.new(dir).join(release_identifier, "CHANGELOG.md")

              if generated_path.exist?
                if current_path.exist? && current_path.read == generated_path.read
                  $stderr.puts "✅ Changelog #{release_identifier} is up to date"
                else
                  $stderr.puts "❌ Changelog #{release_identifier} should be regenerated"
                  success = false
                end
              elsif current_path.exist?
                $stderr.puts "❌ Changelog #{release_identifier} should be regenerated"
                success = false
              end
            end
          end

          success
        end

        def changelog_release_identifiers(releases)
          releases.select(&:published?).map(&:identifier).uniq
        end
      end
    end
  end
end
