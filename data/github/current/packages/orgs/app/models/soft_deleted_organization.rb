# typed: true
# frozen_string_literal: true

#
# We use a whole new table to track soft deletes because of a bad design choice made years ago which prevents us
# from using the current `deleted_at` field as it's stored in the serialized `Users#raw_data` column and we're discouraged
# from making major changes to the users table because it is so large and the cluster so delicate so we can't
# add a `soft_deleted_at` column and index.
#
# Where appropriate, we still use the `deleted_at` and `deleted_by` fields in the serialized `User#raw_data` column.
class SoftDeletedOrganization < ApplicationRecord::Domain::Users
  belongs_to :business, optional: true
  belongs_to :organization

  validates :organization, presence: true, uniqueness: true

  after_destroy_commit :restore_soft_deleted_resources

  private

  sig { void }
  def restore_soft_deleted_resources
    RestoreSoftDeletedOrganizationProjectsJob.perform_later(T.must(organization_id), T.must(created_at).to_i)
    RestoreSoftDeletedOrganizationRepositoriesJob.perform_later(T.must(organization_id), T.must(created_at).to_i)
  end
end
