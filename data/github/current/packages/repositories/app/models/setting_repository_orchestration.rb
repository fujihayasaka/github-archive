# typed: true
# frozen_string_literal: true

class SettingRepositoryOrchestration < SettingOrchestration
  job_start

  step :validate_repo do
    return [:skipped, "repository id is nil"] if repository_id.nil?

    repository = Repositories::Public.find_active(T.must(repository_id))
    return [:skipped, "not active #{repository_id}"] unless repository

    # assign the repo to the root group if it doesn't have a group
    repository.ensure_group

    # double check this repos lives under this group path.
    return [:skipped, "not in group '#{group_path}'"] unless repository.in_group?(group_path)
  end

  step :fork do
    apply(ForkGroupSetting)
  end

  step :access do
    apply(AccessGroupSetting)
  end

  ### add new RepositoryGroupSetting steps above here ###

  def apply(klass)
    return unless types.include?(klass.to_s)
    return unless setting = klass.for_repository(repository)
    setting.apply(actor:, repository:)
  end

  def only_save_on_orchestration_end?
    true
  end

  # For now, let multiple setting orchestrations run for the same repository,
  # because they may be applying different settings.
  # Although this introduces the possibility of race conditions which we need to think through.
  protected def target_uniqueness_condition_on_start; end
end
