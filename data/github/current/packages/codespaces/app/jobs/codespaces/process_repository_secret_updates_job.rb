# typed: true
# frozen_string_literal: true
module Codespaces

  # Background job to find the codespaces impacted by a repository secret change,
  # and to asynchronously fire a secret update job for each of them.
  class ProcessRepositorySecretUpdatesJob < ProcessSecretUpdatesJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    def perform(repository:)
      codespaces = Codespace.where(repository: repository).select do |codespace|
        # This isn't strictly necessary as `process_codespaces` ends up calling UpdateUserSecrets which uses
        # Secret.assemble which checks this as well but it avoids scheduling things unnecessarily.
        Codespaces::Policy.can_receive_secrets?(codespace)
      end
      process_codespaces(codespaces: codespaces)
    end
  end
end
