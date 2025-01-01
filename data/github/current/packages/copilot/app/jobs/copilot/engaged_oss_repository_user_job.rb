# typed: strict
# frozen_string_literal: true

module Copilot
  class EngagedOssRepositoryUserJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    extend T::Sig
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    gate_with_feature_flag :copilot_engaged_oss_job

    sig { params(repository_id: Integer).void }
    def perform(repository_id)
      repository = ::Repository.where(id: repository_id).first

      unless repository
        GitHub.logger.info(
          "Repository not found",
          "gh.copilot.flag_enabled" => flag_enabled,
          "gh.repo.id" => repository_id,
        )
        return false
      end

      Copilot::RepositoryUserLoader.call(repository)
    end
  end
end
