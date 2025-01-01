# typed: true
# frozen_string_literal: true

class HydroCodespacesOnPushJob < Repositories::PushHydroMessageJob
  use_primaries ApplicationRecord::Collab

  queue_as :hydro_codespaces_on_push

  def perform
    return unless GitHub.codespaces_enabled?

    ref_updates.each do |ref_update|
      trigger_prebuild_template_creation(ref_update.branch_name, ref_update.after, ref_update.before)
      Codespaces::VerifyCreationMetadataOnPush.call(
        repository:,
        branch_name: ref_update.branch_name,
        user: pusher,
        force_pushed: ref_update.non_fast_forward?
      )

      if ref_update.created? && ref_update.branch_name.start_with?(Codespace::EXPORT_BRANCH_PREFIX)
        Codespace.find_by(
          name: ref_update.branch_name.delete_prefix(Codespace::EXPORT_BRANCH_PREFIX),
          repository_id: repository_id,
          owner_id: pusher.id
        )&.exported!
      end

      if ref_update.deleted? && ref_update.ref.start_with?("refs/heads/") && ref_update.branch_name.length > 0
        Codespaces::PrebuildConfiguration.destroy_prebuilds(
          branch: ref_update.branch_name,
          repository: repository
        )
      end
    end
  end

  def trigger_prebuild_template_creation(branch_name, sha_after_push, sha_before_push)
    return unless repository.owner&.codespaces_feature_enabled? && repository.actions_enabled?

    configurations = Codespaces::PrebuildConfiguration.where(repository: repository, branch: branch_name).includes(:locations)
    return if configurations.empty?

    configurations.each do |configuration|
      case configuration.trigger.to_sym
      when :push
        configuration.trigger_prebuild_template_creation(commit_sha: sha_after_push)
      when :configuration
        configuration.trigger_prebuild_template_creation(commit_sha: sha_after_push, previous_sha: sha_before_push)
      end
    end
  end
end
