# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    autoload :BundledReleaseWriter, "open_api/description/bundled_release_writer"
    autoload :Changeset, "open_api/description/changeset"
    autoload :ChangesetSchedule, "open_api/description/changeset_schedule"
    autoload :DereferencedReleaseWriter, "open_api/description/dereferenced_release_writer"
    autoload :Operation, "open_api/description/operation"
    autoload :Overlay, "open_api/description/overlay"
    autoload :BreakingChanges, "open_api/description/breaking_changes"
    autoload :Parameter, "open_api/description/parameter"
    autoload :Release, "open_api/description/release"
    autoload :ReleaseSpecification, "open_api/description/release_specification"
    autoload :ReleaseWriter, "open_api/description/release_writer"
    autoload :RequestBody, "open_api/description/request_body"
    autoload :Responses, "open_api/description/responses"
    autoload :Root, "open_api/description/root"
    autoload :Schema, "open_api/description/schema"
    autoload :SchemaValidator, "open_api/description/schema_validator"
    autoload :UnbundledReleaseWriter, "open_api/description/unbundled_release_writer"
    autoload :ValidationResult, "open_api/description/validation_result"
    autoload :VersionedOperation, "open_api/description/versioned_operation"
    autoload :Expander, "open_api/description/expander"

    class ChangesetError < StandardError; end
    class InvalidChangesetError < ChangesetError; end
    class InvalidChangesetNameError < ChangesetError; end

    module_function

    def load_from_yaml(yaml)
      root = YAML.load(yaml)
      OpenApi::Description::Root.new(root)
    end
  end
end
