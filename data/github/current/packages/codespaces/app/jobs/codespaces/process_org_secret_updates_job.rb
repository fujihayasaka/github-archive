# typed: true
# frozen_string_literal: true
module Codespaces

  # Background job to find the codespaces impacted by a organization secret change,
  # and to asynchronously fire a secret update job for each of them.
  class ProcessOrgSecretUpdatesJob < ProcessSecretUpdatesJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    def perform(selected_repository_global_ids:, org:)
      repository_ids = selected_repository_global_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i }
      codespaces = Codespace.where(billable_owner: org, repository: repository_ids).select do |codespace|
        # This isn't strictly necessary as `process_codespaces` ends up calling UpdateUserSecrets which uses
        # Secret.assemble which checks this as well but it avoids scheduling things unnecessarily.
        Codespaces::Policy.can_receive_secrets?(codespace)
      end
      process_codespaces(codespaces: codespaces)
    end
  end
end
