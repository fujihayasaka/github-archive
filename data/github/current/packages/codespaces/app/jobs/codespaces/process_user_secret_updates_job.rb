# typed: true
# frozen_string_literal: true
module Codespaces

  # Background job to find the codespaces impacted by a user secret change,
  # and to asynchronously fire a secret update job for each of them.
  class ProcessUserSecretUpdatesJob < ProcessSecretUpdatesJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    def perform(selected_repository_global_ids:, user:)
      repository_ids = selected_repository_global_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i }
      codespaces = Codespace.where(owner: user, repository: repository_ids)
      process_codespaces(codespaces: codespaces)
    end
  end
end
