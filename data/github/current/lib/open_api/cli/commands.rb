# typed: true
# frozen_string_literal: true

module OpenApi
  module CLI
    module Commands
      autoload :AssignOperationIds, "open_api/cli/commands/assign_operation_ids"
      autoload :Command, "open_api/cli/commands/command"
      autoload :GenerateRootFiles, "open_api/cli/commands/generate_root_files"
      autoload :Bundle, "open_api/cli/commands/bundle"
      autoload :Changeset, "open_api/cli/commands/changeset"
      autoload :Create, "open_api/cli/commands/create"
      autoload :CreateOperation, "open_api/cli/commands/create_operation"
      autoload :CreateExample, "open_api/cli/commands/create_example"
      autoload :Overlays, "open_api/cli/commands/overlays"
      autoload :Patch, "open_api/cli/commands/patch"
      autoload :KustoFilter, "open_api/cli/commands/kusto_filter"
      autoload :VerifyRootFiles, "open_api/cli/commands/verify_root_files"
      autoload :PrepareApiVersionRelease, "open_api/cli/commands/prepare_api_version_release"
      autoload :ListReleases, "open_api/cli/commands/list_releases"
    end
  end
end
