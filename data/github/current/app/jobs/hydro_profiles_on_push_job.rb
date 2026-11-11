# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class HydroProfilesOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_profiles_on_push

  # Public: process a Hydro message
  sig { void }
  def perform
    ref_updates.each do |ref_update|
      next unless ref_update.recordable?

      unless CommitContribution.backfill(repository)
        CommitContribution.track_push(ref_update: ref_update)
      end
    end

    ref_updates.each do |ref_update|
      next unless ref_update.recordable?

      if repository.user_configuration_repository? && ref_update.readme_changed?
        GlobalInstrumenter.instrument("user.profile_readme_action", {
          repository: repository,
          owner: repository.owner,
          actor: pusher,
          change_type: ref_update.readme_change.change_type,
          readme_body: repository.preferred_readme&.data
        })
      end

      if repository.is_org_profile_repository? && ref_update.org_profile_readme_changed?
        GlobalInstrumenter.instrument("organization.profile_readme_action", {
          repository: repository,
          owner: repository.owner,
          actor: pusher,
          change_type: ref_update.org_profile_readme_change.change_type,
          readme_body: repository.org_profile_readme&.data
        })
      end
    end
  end
end
