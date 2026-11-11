# typed: false
# frozen_string_literal: true

require "action_view/helpers/number_helper"
require "open3"
require "tempfile"
require_relative "../../../../app/api/versioning"
require_relative "generate_root_files"

module OpenApi
  module CLI
    module Commands
      class PrepareApiVersionRelease < Command
        include ::ActionView::Helpers::NumberHelper

        INVALID_RELEASE_DATE_ERROR_MSG = <<~ERR
          Invalid date `%s`. By convention we use ISO-8601 format (YYYY-MM-DD).
        ERR

        GENERATED_COMMENT = "# This changeset was released in API version `%s`"
        API_VERSIONS_PATTERN = /(GitHub\.api_versions\s*=\s*%w\[)([^\]]*)(\])/m
        API_VERSION_DEPRECATION_DATES_BLOCK_PATTERN = /GitHub\.api_version_deprecation_dates\s*=\s*\{\n.*?^\}/m
        API_VERSION_DEPRECATION_DATES_ENTRY_PATTERN = /["']([^"']+)["']\s*=>\s*["']([^"']+)["']/

        def run(release_date, dry_run: false, fix: false)
          # validate the version
          begin
            # Reassign release_date to the parsed version to satisfy security linters
            release_date = Date.iso8601(release_date).iso8601
          rescue Date::Error
            raise ArgumentError, INVALID_RELEASE_DATE_ERROR_MSG % release_date
          end

          say "\n--------------------------------------------------------------------------------", :blue
          say "🚀 Preparing release for API version: #{release_date}!", :blue
          say "--------------------------------------------------------------------------------\n", :blue

          # Check for existing PR and extract tracking issue URL and GHES target
          branch_name = "api-calendar-version-release-#{release_date}"
          existing_tracking_url = nil
          existing_ghes_target = nil
          existing_pr_body, = Open3.capture2("gh", "pr", "list", "--head", branch_name, "--json", "body", "--jq", ".[0].body")
          existing_pr_body = existing_pr_body.strip
          if existing_pr_body.present?
            if (match = existing_pr_body.match(/\*\*Tracking Issue\*\*:\s*(\S+)/))
              existing_tracking_url = match[1]
            end
            if (match = existing_pr_body.match(/\*\*GHES Target\*\*:\s*`([^`]+)`/))
              existing_ghes_target = match[1] if match[1].present? && match[1] != ""
            end
          end

          # Prompt for tracking issue
          say "Before we begin, create a tracking issue in github/api-platform using the 'API Calendar Version Release Tracking' template."
          say "Issue template: https://github.com/github/api-platform/issues/new?template=api-versioning-release-template.yml"
          say "Once created, paste the issue URL below. This will be linked in the PR description.", :yellow

          if existing_tracking_url.present?
            say "Detected existing tracking issue: #{existing_tracking_url}", :cyan
            prompt = "Tracking issue URL (Press Enter to keep existing)"
          else
            prompt = "Tracking issue URL (Press Enter to skip)"
          end

          tracking_issue_url = ask(prompt, :green)
          tracking_issue_url = tracking_issue_url.strip if tracking_issue_url.present?

          if tracking_issue_url.blank? && existing_tracking_url.present?
            tracking_issue_url = existing_tracking_url
            say "Using existing tracking issue: #{tracking_issue_url}", :cyan
          end

          # retrieve all releases
          all_releases = OpenApi::Description::Release.find_all(include_unpublished: true)

          # filter GHES releases as available options
          ghes_releases = all_releases.filter_map do |release|
            # should display options based on the latest unpublished (i.e. published: false) GHES release configs
            release.version.version if !release.published? && !release.deprecated? && release.identifier.match?(/ghes/) && !release.identifier.match?(/99.99/)
          end

          # select GHES release target
          say "First, we'll need to decide the GHES release target."
          say "Run the chatops command `.ghe release-dates` in Slack to determine what's available given #{Date.iso8601(release_date).strftime("%B %d, %Y")} meets the feature freeze date. If the GHES release target is unknown at this time, you may omit it for now and re-run this script later to apply it.", :yellow

          if existing_ghes_target.present?
            say "Detected existing GHES target: #{existing_ghes_target}", :cyan
          end

          ghes_release_target = nil

          while ghes_release_target.blank?
            prompt = if existing_ghes_target.present?
              "GHES release target #{ghes_releases} (Press Enter to keep #{existing_ghes_target})"
            else
              "GHES release target #{ghes_releases} (Press Enter to skip)"
            end
            ghes_release_target = ask(prompt, :green)

            if ghes_release_target.blank? && existing_ghes_target.present?
              ghes_release_target = existing_ghes_target
              say "Using existing GHES target: #{ghes_release_target}", :cyan
            end

            break if ghes_release_target.blank?

            unless ghes_releases.include?(ghes_release_target)
              say "Invalid GHES release target. Please select from the options available.", :red
              ghes_release_target = nil
            end
          end

          ghes_release_target_requirement = if ghes_release_target.present?
            Gem::Requirement.new(">= #{ghes_release_target}")
          end

          # update `x-github-api-versions` for OpenAPI description bundling
          say "\nUpdating release configs to support #{release_date}:"
          updated_releases = []
          all_releases.each do |release|
            next if release.identifier.match?(/99.99/) # may want to apply every version to GHES 99.99
            if release.identifier.match?(/ghes/)
              next unless ghes_release_target_requirement&.satisfied_by?(release.version)
            end

            updated_releases << release.identifier
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
            release.write_config unless dry_run
          end
          say "\nRelease configs updated." unless dry_run

          # find all candidate changesets (version: next or already tagged with release_date)
          candidate_changesets = OpenApi::Description::Changeset.all.select do |changeset|
            changeset.version == :next || changeset.version.to_s == release_date
          end

          # split into ready (has a date on or before release) vs. not ready (missing or future date)
          not_ready_changesets, changesets = candidate_changesets.partition do |changeset|
            changeset.ready_to_ship_on_or_after.blank? || Date.parse(changeset.ready_to_ship_on_or_after) > Date.parse(release_date)
          end

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
          tmp_no_tests = %w[remove_string_type_from_repo_id_param remove_singular_assignee_from_issues_and_pull_requests]

          changesets_without_tests = changesets.reject { |cs| changesets_with_tests.key?(cs.name) || tmp_no_tests.include?(cs.name) }
          promoted_changesets = changesets.select { |cs| changesets_with_tests.key?(cs.name) || tmp_no_tests.include?(cs.name) }

          if dry_run
            say "\n[DRY RUN] No files will be modified.", :yellow
            say "\n[DRY RUN] Promoted changesets (#{promoted_changesets.count}):", :green
            promoted_changesets.each { |cs| say "  \u2713 #{cs.name} (#{cs.owner})", :green }
            if not_ready_changesets.any?
              say "\n[DRY RUN] Excluded changesets due to missing or future `ready_to_ship_on_or_after` date (#{not_ready_changesets.count}):", :red
              not_ready_changesets.each { |cs| say "  \u25cb #{cs.name} (#{cs.owner}) [#{cs.ready_to_ship_on_or_after.presence || 'no date'}]", :red }
            end
            if changesets_without_tests.any?
              say "\n[DRY RUN] Excluded changesets due to missing tests (#{changesets_without_tests.count}):", :red
              changesets_without_tests.each { |cs| say "  \u2717 #{cs.name} (#{cs.owner})", :red }
            end
            say "\n[DRY RUN] Run without --dry-run when ready to apply changes.", :yellow
            return
          end

          say "\nThe following tests will automatically use the new version of its corresponding changeset:\n", :green
          changesets_with_tests.each do |name, files|
            puts "\u2713 #{name}: #{files.join("\n\t- ").prepend("\n   - ")}"
          end

          if not_ready_changesets.any?
            say "\nThe following changesets are not ready (missing or future `ready_to_ship_on_or_after` date):"
            not_ready_changesets.each { |cs| say "  \u25cb #{cs.name} (#{cs.owner}) [#{cs.ready_to_ship_on_or_after.presence || 'no date'}]", :yellow }
            say "\nThese changesets will NOT be promoted.", :yellow
          end

          if changesets_without_tests.any?
            say "\nNo tests were detected for: #{changesets_without_tests.map(&:name).join("\n\u2717 ").prepend("\n\u2717 ")}"
            say "\nPlease confirm with the owning team if no tests are needed for these changesets.", :red
            say "\nThese changesets will NOT be promoted.", :red
          end

          # Sync affected_endpoints only for changesets being promoted
          promoted_changeset_names = promoted_changesets.map(&:name)
          sync_result = OpenApi::Description::ChangesetAffectedEndpointsUpdater.sync(fix: fix, changeset_names: promoted_changeset_names)
          stale_paths = sync_result[:stale_paths]
          updated_paths = sync_result[:updated_paths]

          if updated_paths.any?
            say "Updated affected_endpoints for #{updated_paths.count} changeset files.", :green
          end

          if stale_paths.any?
            if fix
              say "Fixed stale affected_endpoints for #{stale_paths.count} changeset files.", :green
            else
              say "affected_endpoints are out of date in #{stale_paths.count} changeset files.", :red
              stale_paths.first(20).each do |path|
                relative = path.relative_path_from(OpenApi.root)
                say "- #{relative}", :red
              end
              if stale_paths.count > 20
                say "- ...and #{stale_paths.count - 20} more", :red
              end
              raise ArgumentError, "Run `bin/openapi prepare_api_version_release #{release_date} --fix` to update affected_endpoints."
            end
          end

          say "\nPromoting #{promoted_changesets.count} changesets to #{release_date}:", :green
          changeset_summary = []

          # promote each changeset to the release date
          promoted_changesets.each do |changeset|
            file_path = OpenApi.root.join("changesets", changeset.filename)
            content = File.read(file_path)

            # Prepend the comment if it doesn't already exist
            unless content.include?(GENERATED_COMMENT % release_date)
              content = GENERATED_COMMENT % release_date + "\n" + content
            end

            # Update version from next to release_date
            # Process line-by-line to avoid unsafe regex anchors (^/$)
            lines = content.lines
            lines.map! do |line|
              if line.match?(/\Aversion:\s*['"]?next['"]?\s*\z/)
                "version: '#{release_date}'\n"
              else
                line
              end
            end

            # Update GHES release target
            # Finds "- ghes" (with optional trailing content) and replaces it with the versioned constraint
            if ghes_release_target.present?
              # Remove TODO comment if present from a previous run
              lines.reject! { |line| line.match?(/\A# TODO: GHES release version to be determined\s*\z/) }

              # Update GHES release line
              lines.map! do |line|
                if (match = line.match(/\A(\s*-\s*)ghes/))
                  "#{match[1]}ghes: \">= #{ghes_release_target}\"\n"
                else
                  line
                end
              end
            else
              # Add a TODO comment above ghes line if not already present
              unless lines.any? { |line| line.start_with?("# TODO: GHES release version to be determined") }
                lines.map! do |line|
                  if line.match?(/\A\s*-\s*ghes/)
                    "# TODO: GHES release version to be determined\n#{line}"
                  else
                    line
                  end
                end
              end
            end

            content = lines.join

            say "- #{changeset.name} owned by #{changeset.owner}"
            changeset_summary << "- #{changeset.name} (@#{changeset.owner.delete('@')})"
            File.write(file_path, content)
          end

          say "\nChangesets promoted."

          # Update static list of supported versions
          config_path = "lib/github/config/environments/default.rb"
          content = File.read(config_path)
          updated_content = updated_environment_config_content(content, release_date, config_path)
          if updated_content != content
            File.write(config_path, updated_content)
          end

          # generate changelogs for new calendar version
          say "\nGenerating changelogs for #{release_date}:"
          written_files = OpenApi::Description::ChangelogGenerator.generate_all
          written_files.each do |file_path|
            relative_path = file_path.relative_path_from(GitHub::AppEnvironment.root)
            say "- #{relative_path}", :green
          end
          say "Changelogs generated for #{release_date}."

          # generate root files
          say "\n⚙️  Re-generating root files for the new version...", :cyan
          GenerateRootFiles.new(@shell).run(updated_releases)
          say "✅  Root files generated.", :green

          say "\n#{'=' * 80}", :green
          say "🎉  DONE! API version #{release_date} is ready to be released.  🎉", :green
          say "#{'=' * 80}\n", :green

          # Automatically create branch and PR
          # switch to branch
          say "Checking out branch #{branch_name}..."
          system("git", "checkout", "-b", branch_name) || system("git", "checkout", branch_name)

          say "Committing changes..."
          system("git", "add", ".")
          system("git", "commit", "-m", "API Release #{release_date}")

          say "Pushing to origin..."
          system("git", "push", "-u", "origin", branch_name)

          say "Creating Pull Request..."

          promoted_section = ""
          if changeset_summary.any?
            promoted_section = <<~SECTION

              ## 📦 Promoted Changesets
              #{changeset_summary.join("\n")}
            SECTION
          end

          omitted_section = ""
          if changesets_without_tests.any? || not_ready_changesets.any?
            omitted_body = ""
            if not_ready_changesets.any?
              omitted_body += "\n### ⏳ Missing or Future `ready_to_ship_on_or_after`\n"
              omitted_body += not_ready_changesets.map { |cs| "- #{cs.name} (@#{cs.owner.delete('@')}) [#{cs.ready_to_ship_on_or_after.presence || 'no date'}]" }.join("\n")
              omitted_body += "\n"
            end
            if changesets_without_tests.any?
              omitted_body += "\n### ⚠️ Missing Tests\n"
              omitted_body += changesets_without_tests.map { |cs| "- #{cs.name} (@#{cs.owner.delete('@')})" }.join("\n")
              omitted_body += "\n"
            end
            omitted_section = <<~SECTION

              ## 🚫 Omitted Changesets
              #{omitted_body.strip}
            SECTION
          end

          tracking_section = ""
          if tracking_issue_url.present?
            tracking_section = <<~SECTION

              ## 🔗 Release Tracking
              - **Tracking Issue**: #{tracking_issue_url}
            SECTION
          end

          pr_body = <<~BODY
            # API Release #{release_date}

            🚀 Auto-generated preparation for API version `#{release_date}`.

            #{tracking_section}
            ## 📋 Summary
            - **Target Date**: #{release_date}
            - **GHES Target**: `#{ghes_release_target}`
            - **Promoted Changesets**: #{promoted_changesets.count}
            #{promoted_section}#{omitted_section}
            ## ✅ Verification
            1. Verify `lib/github/config/environments/default.rb` includes `#{release_date}`.
            2. Check generated root files in `app/api/description/`.
            3. Review CI for affected test cases.
          BODY

          pr_body_file = Tempfile.new("pr_body")
          begin
            pr_body_file.write(pr_body)
            pr_body_file.close

            # Check if PR already exists for this branch
            existing_pr, = Open3.capture2("gh", "pr", "list", "--head", branch_name, "--json", "number", "--jq", ".[0].number")
            existing_pr = existing_pr.strip
            if existing_pr.empty?
              say "Creating new Pull Request..."
              system("gh", "pr", "create", "--draft", "--title", "API Release #{release_date}", "--body-file", pr_body_file.path, "--base", "master", "--head", branch_name)
            else
              say "Updating existing Pull Request ##{existing_pr}..."
              system("gh", "api", "--method", "PATCH", "/repos/{owner}/{repo}/pulls/#{existing_pr}", "-F", "body=@#{pr_body_file.path}", out: File::NULL)
              say "✅ PR ##{existing_pr} updated.", :green
            end
          ensure
            pr_body_file.unlink
          end
        end

        private

        def updated_environment_config_content(content, release_date, config_path)
          updated_content, api_versions_status = ensure_release_date_in_api_versions(content, release_date)

          case api_versions_status
          when :updated
            say "Added #{release_date} to #{config_path}", :green
          when :unchanged
            say "#{release_date} already exists in #{config_path}", :yellow
          else
            ask "\nNext, we'll need to update the environment config to support the new version. Add '#{release_date}' to the existing list of supported API versions (`GitHub.api_versions`) in 'lib/github/config/environments/default.rb'. \nPress enter once completed", :red
            return content
          end

          updated_content, deprecation_dates_result = ensure_api_version_deprecation_dates(updated_content, release_date)

          case deprecation_dates_result[:status]
          when :updated
            say "Set #{deprecation_dates_result[:version]} deprecation date to #{deprecation_dates_result[:deprecation_date]} in #{config_path}", :green
          when :unchanged
            if deprecation_dates_result[:version]
              say "#{deprecation_dates_result[:version]} already has deprecation date #{deprecation_dates_result[:deprecation_date]} in #{config_path}", :yellow
            end
          when :initialized
            say "Initialized GitHub.api_version_deprecation_dates in #{config_path}", :green
          when :skipped
            say "No prior API version found to deprecate in #{config_path}", :yellow
          end

          updated_content
        end

        def ensure_release_date_in_api_versions(content, release_date)
          match = content.match(API_VERSIONS_PATTERN)
          return [content, :missing] unless match

          prefix, dates, suffix = match[1], match[2], match[3]
          return [content, :unchanged] if dates.split.include?(release_date)

          sorted_versions = sort_api_versions(dates.split + [release_date])
          new_dates = "\n#{sorted_versions.map { |v| "  #{v}" }.join("\n")}\n"
          [content.sub(API_VERSIONS_PATTERN, "#{prefix}#{new_dates}#{suffix}"), :updated]
        end

        def ensure_api_version_deprecation_dates(content, release_date)
          release_versions = sort_api_versions(extract_api_versions(content))
          release_index = release_versions.index(release_date)
          previous_version = release_index ? release_versions[release_index + 1] : nil
          deprecation_date = nil
          deprecation_dates = extract_api_version_deprecation_dates(content)

          status = if previous_version.nil?
            content.match?(API_VERSION_DEPRECATION_DATES_BLOCK_PATTERN) ? :skipped : :initialized
          else
            deprecation_date = (Date.iso8601(release_date) >> 6).iso8601
            if deprecation_dates[previous_version] == deprecation_date && content.match?(API_VERSION_DEPRECATION_DATES_BLOCK_PATTERN)
              :unchanged
            else
              deprecation_dates[previous_version] = deprecation_date
              :updated
            end
          end

          updated_content = if status == :skipped && content.match?(API_VERSION_DEPRECATION_DATES_BLOCK_PATTERN)
            content
          else
            upsert_api_version_deprecation_dates_block(content, deprecation_dates)
          end

          [updated_content, { status:, version: previous_version, deprecation_date: }]
        end

        def extract_api_versions(content)
          match = content.match(API_VERSIONS_PATTERN)
          return [] unless match

          match[2].split
        end

        def extract_api_version_deprecation_dates(content)
          block = content[API_VERSION_DEPRECATION_DATES_BLOCK_PATTERN]
          return {} if block.nil?

          block.scan(API_VERSION_DEPRECATION_DATES_ENTRY_PATTERN).to_h
        end

        def sort_api_versions(versions)
          versions.sort_by { |version| Date.iso8601(version) }.reverse
        end

        def sort_api_version_deprecation_dates(deprecation_dates)
          deprecation_dates.sort_by { |version, _| Date.iso8601(version) }.reverse.to_h
        end

        def upsert_api_version_deprecation_dates_block(content, deprecation_dates)
          formatted_block = format_api_version_deprecation_dates_block(deprecation_dates)

          if content.match?(API_VERSION_DEPRECATION_DATES_BLOCK_PATTERN)
            content.sub(API_VERSION_DEPRECATION_DATES_BLOCK_PATTERN, formatted_block)
          else
            content.sub(API_VERSIONS_PATTERN) do |matched_block|
              "#{matched_block}\n\n#{formatted_block}"
            end
          end
        end

        def format_api_version_deprecation_dates_block(deprecation_dates)
          entries = sort_api_version_deprecation_dates(deprecation_dates).map { |version, deprecation_date| "  \"#{version}\" => \"#{deprecation_date}\",\n" }.join

          "GitHub.api_version_deprecation_dates = {\n#{entries}}"
        end
      end
    end
  end
end
