# typed: true
# frozen_string_literal: true

require "thor"

module OpenApi
  module CLI
    class Root < Thor
      package_name "openapi"

      # https://github.com/erikhuda/thor/issues/244
      def self.exit_on_failure?
        true
      end

      desc "generate_root_files [release-version otherrelease-version ...]", "Generate the OpenAPI root files for all (or specified) versions."
      def generate_root_files(*release_identifiers)
        OpenApi::CLI::Commands::GenerateRootFiles.run(shell, release_identifiers)
      end

      desc "bundle -o <destination> [release-version otherrelease-version ...]", "Generates the dereferenced files for all (or specified) GitHub API versions into a target directory"
      method_option :output, aliases: "-o", required: true, desc: "Output directory"
      method_option :include_unpublished, aliases: "-i", desc: "Bundle OpenAPI descriptions that aren't published yet."
      method_option :include_deprecated, aliases: "-d", desc: "Bundle OpenAPI descriptions that are deprecated."
      method_option :api_versioned, aliases: "-v", desc: "Bundle OpenAPI descriptions with support for API Versions"
      method_option :include_next_version, aliases: "-n", desc: "Include the 'next' version when bundling OpenAPI descriptions with support for API Versions"
      method_option :include_webhooks, aliases: "-w", desc: "Bundle OpenAPI webhook descriptions."
      method_option :generate_dref_json_only, desc: "Only generate the deferenced JSON files to speed up docs local development."
      def bundle(*release_identifiers)
        OpenApi::CLI::Commands::Bundle.run(
          shell,
          options[:output],
          release_identifiers,
          include_unpublished: options.key?(:include_unpublished),
          include_deprecated: options.key?(:include_deprecated),
          include_api_versions: options.key?(:api_versioned),
          include_next_version: options.key?(:include_next_version),
          include_webhooks: options.key?(:include_webhooks),
          generate_dref_json_only: options.key?(:generate_dref_json_only)
        )
      end

      desc "prepare_api_version_release <release_date>", "Prepare an API version release"
      def prepare_api_version_release(release_date)
        OpenApi::CLI::Commands::PrepareApiVersionRelease.run(shell, release_date)
      end

      desc "create", "Create a new OpenAPI object."
      subcommand "create", OpenApi::CLI::Commands::Create

      desc "changeset", "Generates summary of changeset descriptions"
      subcommand "changeset", OpenApi::CLI::Commands::Changeset

      desc "checksum", "Outputs a checksum for the current OpenAPI document"
      def checksum
        puts OpenApi.checksum
      end

      desc "patch <file1>, <file2>, ...", "Patch YAML files with patch given in STDIN"
      def patch(*files)
        OpenApi::CLI::Commands::Patch.run(shell, files)
      end

      desc "format [--full]", "Ensure all OpenAPI files are consistently formatted"
      method_option :full, aliases: "-f", type: :boolean, default: false, desc: "Apply full formatting to files"
      def format
        OpenApi::CLI::Commands::Format.run(shell, options)
      end

      desc "kusto-filter", "Generate Kusto regular expressions for SLA dashboard (SLA Tier 1)"
      def kusto_filter
        OpenApi::CLI::Commands::KustoFilter.run(shell)
      end

      desc "verify_root_files [release-version otherrelease-version ...]", "Verifies if the OpenAPI root files (for specified releases, if given) need regeneration. Exits with 1 if anything has changed"
      def verify_root_files(*release_identifiers)
        success = OpenApi::CLI::Commands::VerifyRootFiles.run(shell, release_identifiers)
        exit(success ? 0 : 1)
      end

      desc "validate_operations [--cleanup-orphaned]", "Validate operations found in repository. Exits with 1 if any problems found"
      method_option :cleanup_orphaned, type: :boolean, default: false, desc: "Cleanup orphaned operations"
      def validate_operations
        success = OpenApi::CLI::Commands::ValidateOperations.validate(cleanup_orphaned: options[:cleanup_orphaned])
        exit(success ? 0 : 1)
      end

      desc "current-release", "Outputs the current release identifier, checking the current application configuration"
      def current_release
        puts OpenApi::Description::Release.current(include_unpublished: true)
      end

      desc "overlays", "See and modify overlays"
      subcommand "overlays", OpenApi::CLI::Commands::Overlays

      desc "assign-operation-ids [OPTIONS]", "Assign Operation IDs"
      method_option :dry_run, aliases: "-d", type: :boolean, default: false, desc: "Generate CSV report instead of modifying code"
      def assign_operation_ids
        OpenApi::CLI::Commands::AssignOperationIds.run(shell, dry_run: options[:dry_run])
      end

      desc "list-releases [--include-unpublished]", "Output the supported releases currently in the repository"
      method_option :include_unpublished, type: :boolean, default: false, desc: "Include future releases which are not yet published"
      def list_releases
        OpenApi::CLI::Commands::ListReleases.list(include_unpublished: options[:include_unpublished])
      end
    end
  end
end
