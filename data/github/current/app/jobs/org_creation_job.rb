# typed: true
# frozen_string_literal: true

class OrgCreationJob < ApplicationJob
  queue_as :org_creation

  def perform(creator_id, org_id)
    return if GitHub.enterprise?
    return unless @creator = User.find_by(id: creator_id)
    return unless @org = Organization.find_by(id: org_id)

    org.admins.where.not(id: creator.id).each do |admin|
      OrganizationMailer.admin_added(admin, org, creator).deliver_now
    end
  end

  private

  attr_reader :creator, :org
end
