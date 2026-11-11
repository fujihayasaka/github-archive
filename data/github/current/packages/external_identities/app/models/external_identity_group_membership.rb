# typed: true
# frozen_string_literal: true

class ExternalIdentityGroupMembership < ApplicationRecord::Domain::Users
  # Note: this class is deleted using `delete_all` method and will not trigger
  # any callbacks. If you need to do something when a membership is deleted,
  # the changes need to be made how this class is deleted first in the base_group_provisioner
  class UserNotLinkedError < StandardError; end

  belongs_to :external_group
  belongs_to :external_identity

  validates_presence_of :external_group, :external_identity
end
