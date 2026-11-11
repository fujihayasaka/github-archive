# typed: true
# frozen_string_literal: true

class BulkRemoveOrgMemberForksJob < ApplicationJob
  include GitHub::Memoizer

  attr_accessor :user, :organization_ids

  queue_as :bulk_remove_org_member_forks

  retry_on_dirty_exit

  BATCH_SIZE = 100

  # This is the bulk version of RemoveOrgMemberForksJob
  # IMPORTANT: It does not create restorable records for each starred repo
  # If you need that, use the non-bulk version of the job
  def perform(user_id:, organization_ids:, send_email: false)
    @organization_ids = organization_ids
    return unless @user = User.find_by(id: user_id)

    inaccessible_forks.in_batches(of: BATCH_SIZE) do |forks|
      forks_to_remove = not_pullable(forks) { |user_fork| user_fork.parent }

      with_write do
        forks_to_remove.each do |fork|
          fork.remove(nil, send_email:)
        end
      end
    end

    businesses = Set.new

    organization_ids.each do |org_id|
      if org = Organization.find_by(id: org_id)
        if org.business && !businesses.include?(T.must(org.business).id)
          businesses << T.must(org.business).id

          ::RemoveBizUserForksJob.perform_later(biz_id: T.must(org.business).id, belonging_to_user_id: user_id)
        end
      end
    end
  end

  private

  memoize def private_org_repo_fork_ids
    Repository.includes(:parent)
      .where(parents_repositories: { public: false, owner_id: @organization_ids })
      .where(owner_id: @user.id)
      .active
      .pluck(:id)
      .to_a
  end

  memoize def accessible_fork_ids
    user.associated_repository_ids(
      repository_ids: private_org_repo_fork_ids,
      including: [:direct, :indirect],
      include_indirect_forks: false,
    ).to_a
  end

  memoize def inaccessible_forks
    inaccessible_fork_ids = private_org_repo_fork_ids - accessible_fork_ids

    Repository.where(id: inaccessible_fork_ids)
  end

  def not_pullable(batch, &block)
    batch.reject do |repo|
      repo_to_check = block&.call(repo) || repo
      repo_to_check.pullable_by_user_or_no_plan_owner?(user)
    end
  end
end
