# typed: true
# frozen_string_literal: true

class RemoveOrgMemberForksJob < LegacyRemoveOrgMemberDataJob
  queue_as :archive_restore

  # options is used by the base class it is a hash of { "organization_id" => value, "user_id" => value }
  def perform(options)
    org_forks.find_in_batches do |batch|
      inaccessible = inaccessible_org_repos(batch) { |user_fork| user_fork.parent }

      with_write do
        inaccessible.each do |user_fork|
          remove_user_fork(user_fork)
        end
        restorable.save_repositories(inaccessible)
      end
    end

    # If this org is part of a business, also check accessibility of
    # any forks of repos in other orgs having internal visibility.
    ::RemoveBizUserForksJob.perform_later(biz_id: org.business.id, belonging_to_user_id: user.id) if org.business

    with_write { restorable.save_repositories_complete }
  end

  private

  def org_forks
    @org_forks ||= Repository.private_forks_for(organization: org, belonging_to_user: user)
  end

  def remove_user_fork(user_fork)
    user_fork.throttle do
      # No actor is better than the wrong actor.
      # See https://github.com/github/security/issues/3748.
      user_fork.remove(nil, send_email: true)
    end

    GitHub.dogstats.increment("org.repo.archive_fork")
  rescue ActiveRecord::RecordNotFound
    GitHub.dogstats.increment("org.repo.archive_fork_record_not_found")
  end
end
