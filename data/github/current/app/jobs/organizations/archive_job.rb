# typed: strict
# frozen_string_literal: true

module Organizations
  class ArchiveJob < ApplicationJob
    extend T::Sig

    queue_as :organizations_archive
    retry_on_dirty_exit

    sig do
      params(
        org: Organization::ArchivedDependency,
        actor: User,
        by_site_admin: T::Boolean,
      ).void
    end
    def perform(org, actor, by_site_admin: false)
      status = JobStatus.find(org.archive_job_id)
      return unless status.present?

      status.track do
        org.repositories.each do |repo|
          with_write { repo.set_archived }
        end

        with_write { org.set_archived(actor) }

        options = AccountMailer::Serializers.archive_org(
          org,
          admins_to_notify(org),
          actor,
          by_site_admin: by_site_admin
        )
        AccountMailer.archive_org(options).deliver_later
      end
    end

    sig { params(org: Organization::ArchivedDependency).returns(T::Array[User]) }
    def admins_to_notify(org)
      org.admins.select { |admin| !admin.suspended? }
    end
  end
end
