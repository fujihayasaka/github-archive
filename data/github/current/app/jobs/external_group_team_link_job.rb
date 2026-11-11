# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ExternalGroupTeamLinkJob < ApplicationJob
  queue_as :external_group_team_link

  MAX_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 5.minutes
  LOCK_KEY = "external-group-team-link-job:"

  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY = 5.minutes

  retry_on_dirty_exit
  retry_on GitHub::Restraint::UnableToLock, wait: RETRY_DELAY, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
    Failbot.report(error)
  end
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
    Failbot.report(error)
  end

  def perform(external_group_team_id, caller:)
    Failbot.push(external_group_team_id: external_group_team_id)

    unless external_group_team_id
      GitHub.dogstats.increment("external_identities.external_group_team_link_job.no_external_group_team_id")
      return
    end

    external_group_team = ExternalGroupTeam.find_by(id: external_group_team_id)
    unless external_group_team
      GitHub.dogstats.increment("external_identities.external_group_team_link_job.no_external_group_team")
      return
    end

    team = external_group_team.team
    external_group = external_group_team.external_group
    unless team && external_group
      GitHub.dogstats.increment("external_identities.external_group_team_link_job.no_external_group_and_team")
      return
    end

    business = external_group.provider&.business

    GitHub.logger.info(
      "info.message" => "Starting external_group_team_link job",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_group_team.id" => external_group_team_id,
      "gh.external_group.id" => external_group.id,
      "gh.business.id" => business&.id,
      "gh.business.slug" => business&.slug,
       "gh.caller" => caller.to_s
    )

    begin
      lock!(external_group_team_id) do
        external_group_team.reconcile_memberships(job: ExternalGroupTeamLinkJob, job_args: [external_group_team_id], job_kwargs: { caller: self.class.name })
      end

      external_group_team.external_group&.provider.business&.update_license_usage
    ensure
      GitHub.logger.info(
        "info.message" => "Finished external_group_team_link job",
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.external_group_team.id" => external_group_team_id,
        "gh.external_group.id" => external_group.id,
        "gh.business.id" => business&.id,
        "gh.business.slug" => business&.slug,
        "gh.caller" => caller.to_s
      )
    end
  end

  private

  # Private: The restraint for locking and preventing simultaneous reconcile jobs
  # for the same external group team.
  #
  # Returns GitHub::Restraint
  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  # Private: Use a GitHub::Restraint to prevent simultaneous updates
  def lock!(external_group_team_id)
    restraint_key = "#{LOCK_KEY}#{external_group_team_id}"
    restraint.lock!(restraint_key, MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
