# typed: strict
# frozen_string_literal: true

module Organization::ArchivedDependency
  extend T::Helpers

  requires_ancestor { Organization }

  ARCHIVE_JOB_STATUS_BASE_KEY = T.let("organization_archive_job".freeze, String)

  sig { returns(T::Boolean) }
  def archived?
    !!archived_at
  end

  sig { returns(T::Boolean) }
  def archiving?
    job_status = JobStatus.find(archive_job_id)
    job_status.present? && !job_status.finished?
  end

  sig { returns(T::Boolean) }
  def archived_or_archiving?
    return true if archived?

    archiving?
  end

  sig { returns(T::Boolean) }
  def billing_allows_archiving?
    owned_by_business? || on_free_plan?
  end

  sig { returns(String) }
  def archive_job_id
    "#{ARCHIVE_JOB_STATUS_BASE_KEY}_#{id}"
  end

  sig do
    params(
      actor: User,
      by_site_admin: T::Boolean,
    ).returns(T::Boolean)
  end
  def archive(actor, by_site_admin: false)
    return true if archived?
    return false unless actor.present? && permit_archival?(actor)

    JobStatus.create(id: archive_job_id)
    Organizations::ArchiveJob.perform_later(self, actor, by_site_admin: by_site_admin)

    true
  end

  sig { params(actor: User).returns(T::Boolean) }
  def unarchive(actor)
    return true unless archived?
    return false unless actor.present?
    return false unless actor_can_archive?(actor)

    set_unarchived(actor)

    true
  end

  sig { params(actor: User).void }
  def set_archived(actor)
    time = Time.current
    update!(archived_at: time)
    archived_at = time

    instrument :archive, actor: actor
  end

  private

  sig { params(actor: User).void }
  def set_unarchived(actor)
    update!(archived_at: nil)
    archived_at = nil

    instrument :unarchive, actor: actor
  end

  # Check if the organization is permitted to be archived.
  # Right now, we only check the feature flag but this could be extended to check
  # if the org is spammy, is trade-controlled, or similar.
  #
  # Current rules that allow archival:
  # - Feature flag is enabled
  # - Part of an enterprise account / on a free plan
  # - User is an admin
  sig { params(actor: User).returns(T::Boolean) }
  def permit_archival?(actor)
    actor_can_archive?(actor) && billing_allows_archiving?
  end

  sig { params(actor: User).returns(T::Boolean) }
  def actor_can_archive?(actor)
    actor.site_admin? || adminable_by?(actor)
  end

  sig { returns(T::Boolean) }
  def owned_by_business?
    business.present?
  end

  sig { returns(T::Boolean) }
  def on_free_plan?
    plan.free? || plan.free_with_addons?
  end
end
