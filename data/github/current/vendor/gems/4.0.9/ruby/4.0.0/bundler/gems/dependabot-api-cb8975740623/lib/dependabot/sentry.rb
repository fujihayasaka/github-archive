# frozen_string_literal: true

module Dependabot
  class Sentry
    # These keys are used to customize grouping and display of exceptions in Sentry
    SPECIAL_KEYS = %i(app rollup transaction).freeze

    # These keys will be prefixed with "#" which triggers indexing in Sentry
    INDEXED_TELEMETRY_KEYS = %i(
      gh.aqueduct.job.id
      gh.installation.id
      gh.dependabot_api.update_config.package_manager
      gh.dependabot_api.update_job.id
      gh.dependabot_api.pull_request.id
      gh.owner.id
      gh.repo.id
      gh.repo.visibility
    ).to_set.freeze

    def self.tag_indexed_telemetry_attributes(attrs)
      attrs.transform_keys { |key| INDEXED_TELEMETRY_KEYS.include?(key) ? :"##{key}" : key }
    end
  end
end
