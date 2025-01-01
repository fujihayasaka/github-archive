# typed: false
# frozen_string_literal: true

require "action_view/helpers/number_helper"
require_relative "../../../../app/api/versioning"

module OpenApi
  module CLI
    module Commands
      class PrepareApiVersionRelease < Command
        include ::ActionView::Helpers::NumberHelper

        INVALID_RELEASE_DATE_ERROR_MSG = <<~ERR
          Invalid date `%s`. By convention we use ISO-8601 format (YYYY-MM-DD).
        ERR

        GENERATED_COMMENT = "# This changeset was released in API version `%s`"

        def run(release_date)
          # validate the version
          begin
            Date.iso8601(release_date)
          rescue Date::Error
            raise ArgumentError, INVALID_RELEASE_DATE_ERROR_MSG % release_date
          end

          say "\nPreparing release for API version: #{release_date}!\n"

          # retrieve all releases
          all_releases = OpenApi::Description::Release.find_all(include_unpublished: true)

          # filter GHES releases as available options
          ghes_releases = all_releases.filter_map do |release|
            # should display options based on the latest unpublished (i.e. published: false) GHES release configs
            release.version.version if !release.published? && !release.deprecated? && release.identifier.match?(/ghes/) && !release.identifier.match?(/99.99/)
          end

          # select GHES release target
          say "First, we'll need to decide the GHES release target."
          say "Run the chatops command `.ghe release-dates` in Slack to determine what's available given #{Date.iso8601(release_date).strftime("%B %d, %Y")} meets the feature freeze date. If you don't see a specific release option, you'll need to create a new GHES release config in a separate pull request.", :red
          ghes_release_target = nil

          while ghes_release_target.blank?
            ghes_release_target = ask("GHES release target #{ghes_releases}", :green)
            unless ghes_releases.include?(ghes_release_target)
              say "Invalid GHES release target. Please select from the options available.", :red
              ghes_release_target = nil
            end
          end

          ghes_release_target_requirement = Gem::Requirement.new(">= #{ghes_release_target}")

          # update `x-github-api-versions` for OpenAPI description bundling
          say "\nUpdating release configs to support #{release_date}:"
          all_releases.each do |release|
            next if release.identifier.match?(/99.99/) # may want to apply every version to GHES 99.99
            next if release.identifier.match?(/ghes/) && !ghes_release_target_requirement.satisfied_by?(release.version)

            say "- #{release.identifier}"
            release_existing_versions = release.config["patch"].find { |patch| patch["path"] == "/info/x-github-api-versions" }
            if release_existing_versions.nil?
              release.config["patch"] << {
                "op" => "add",
                "path" => "/info/x-github-api-versions",
                "value" => [release_date],
              }
            else
              release_existing_versions["value"] << release_date unless release_existing_versions["value"].include?(release_date)
            end
            release.write_config
          end
          say "\nRelease configs updated."

          # find all ready changesets if the new calendar version meets the condition of the `ready_to_ship_on_or_after` property
          changesets = OpenApi::Description::Changeset.all.select do |changeset|
            changeset.version == :next && changeset.ready_to_ship_on_or_after.present? && Date.parse(changeset.ready_to_ship_on_or_after) <= Date.parse(release_date)
          end

          say "\nPromoting #{changesets.count} changesets to #{release_date}:"

          # promote each changeset to the release date
          changesets.each do |changeset|
            cs = changeset.raw
            # for changesets that target ghes, update its definition file to specify the exact ghes version selected above.
            cs["releases"] = cs["releases"].map do |release|
              if release.match?(/ghes/)
                { release => ">= #{ghes_release_target}" }
              else
                release
              end
            end
            # update `version` property of changeset description files from `next` to new calendar version,
            say "- #{changeset.name} owned by #{changeset.owner}"
            cs["version"] = release_date
            File.write(OpenApi.root.join("changesets", changeset.filename), GENERATED_COMMENT % release_date + "\n" + YAML.dump(cs))
          end

          say "\nChangesets promoted."

          # Update static list of supported versions (also add a linter for this)
          ask "\nNext, we'll need to update the environment config to support the new version. Add '#{release_date}' to the existing list of supported API versions (`GitHub.api_versions`) in 'lib/github/config/environments/default.rb'. \nPress enter once completed", :red

          # Tests for breaking changes should include with_changeset "name_of_changeset".
          # This allows us to easily grep for all tests that will be updated when a changeset is promoted.
          say "\nSearching for test cases ..."

          changesets_with_tests = Hash.new { |h, k| h[k] = [] }
          Dir.glob("**/*.rb").each do |f|
            File.readlines(f).each do |line|
              line.include?("with_changeset") && changesets.any? do |cs|
                if line.include?(cs.name)
                  changesets_with_tests[cs.name] << f
                end
              end
            end
          end
          changesets_without_tests = changesets.reject { |cs| changesets_with_tests.key?(cs.name) }

          say "\nThe following tests will automatically use the new version of its corresponding changeset:\n", :green
          changesets_with_tests.each do |name, files|
            puts "\u2713 #{name}: #{files.join("\n\t- ").prepend("\n   - ")}"
          end

          if changesets_without_tests.any?
            say "\nNo tests were detected for: #{changesets_without_tests.map(&:name).join("\n\u2717 ").prepend("\n\u2717 ")}"
            say "\nPlease confirm with the owning team if no tests are needed for these changesets.", :red
          end

          # generate changelog for new calendar version. We'll figure out where to put it later.
          say "\nGenerating changelog for #{release_date}:"

          say "\n\u{1F389}Done! API version #{release_date} is ready to be released.\u{1F389}"

          # generate root files
          say "Please run `bin/openapi generate_root_files` to re-generate the root files for the new version. Commit all resulting changes and open a pull request.", :red
        end
      end
    end
  end
end
