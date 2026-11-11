# typed: true
# frozen_string_literal: true

class Codespaces::AttachPullRequestJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(pull_request:)
    codespaces = codespaces_to_attach(pull_request)

    if codespaces.any?
      with_write do
        Codespace.throttle_with_retry { codespaces.update(pull_request: pull_request) }
        PullRequestSource.throttle_with_retry { pull_request.pull_request_sources.create(source: :codespace) }
      end
    end
  end

  def codespaces_to_attach(pull_request)
    ActiveRecord::Base.connected_to(role: :reading) do # prefer replica since these are all reads
      return [] unless pull_request && pull_request.user&.codespaces_feature_enabled?
      return [] unless pull_request.head_ref != pull_request.repository.default_branch
      ids = pull_request.user.codespaces.where(repository: pull_request.repository).filter_map { |c| c.id if c.display_branch == pull_request.head_ref }
      Codespace.where(id: ids)
    end
  end
end
