# typed: strict
# frozen_string_literal: true

class RemoveBusinessOrganizationsJob < ApplicationJob
  extend T::Sig

  # TODO: Create a new queue for this job when one can be created without applying for an exception.
  # See https://github.com/github/platform-and-enterprise/discussions/510.
  queue_as :remove_internal_repositories
  retry_on_dirty_exit

  # Public: Remove all member organizations from the business, without
  # destroying the associated Organization records.
  #
  sig { params(business_id: Integer, actor: T.nilable(User)).void }
  def perform(business_id, actor: nil)
    return unless business = Business.find_by(id: business_id)

    business.organizations.each do |org|
      with_write do
        business.remove_organization(org, actor: actor)
      end
    end
  end
end
