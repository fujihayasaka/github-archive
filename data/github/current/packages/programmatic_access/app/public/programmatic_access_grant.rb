# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module ProgrammaticAccessGrant
  ORGANIZATION_TYPE = OrganizationProgrammaticAccessGrant
  MAX_REPOSITORY_SUBSET_LIMIT = ProgrammaticAccessGrantRequest::Service::MAX_REPOSITORY_LIMIT

  def self.null_grant(access, target = nil)
    access.async_owner.then do |owner|
      NullProgrammaticAccessGrant.new(target: (target || owner), user_programmatic_access: access)
    end.sync
  end

  def self.with_bot(target_type, ids: [])
    case target_type.name
    when "Business"
    when "Organization", "User"
      "#{target_type}ProgrammaticAccessGrant".constantize.with_bot(ids: ids)
    end
  end

  def self.with_target(target)
    params = { target: target }
    ProgrammaticAccessGrant::Finder.new(params: params).perform
  end

  def self.with_repository(repository)
    params = { repository: repository }
    ProgrammaticAccessGrant::Finder.new(params: params).perform
  end

  def self.with_repository_and_grant_owner(repository, grant_owner)
    params = { repository: repository, owner: grant_owner }
    ProgrammaticAccessGrant::Finder.new(params: params).perform
  end

  def self.with_target_type_and_access(target_type, access)
    params = { target_type: target_type, access: access }
    ProgrammaticAccessGrant::Finder.new(params: params).perform
  end

  def self.with_target_and_owner(target, owner)
    params = { target: target, owner: owner }
    ProgrammaticAccessGrant::Finder.new(params: params).perform
  end

  # Public:  Finds *ProgrammaticAccessGrant records for a given target
  # and that satisfy the given filters.
  #
  # options - The Hash options used to customize the response.
  #           :target           - The target a grant is associated with.
  #           :filters          - A hash that contains filters to apply to the scope.
  #
  #
  # Example
  # with_target_and_filters(
  #     Organization.first,
  #     { :owner => User.first,
  #       :repository => Repository.first,
  #       :permission => { "actions" => :read } }
  #   )
  #
  #
  # Returns a scope of *ProgrammaticAccessGrant records
  def self.with_target_and_filters(target, filters)
    return ProgrammaticAccessGrant.none if target.nil?

    params = filters.merge({ target: target })
    ProgrammaticAccessGrant::Finder.new(params: params).perform
  end

  def self.from_target_and_id(target, id)
    with_target(target).find_by(id: id)
  end

  def self.from_target_and_ids(target, ids)
    with_target(target).where(id: ids)
  end

  def self.none
    OrganizationProgrammaticAccessGrant.none
  end

  def self.revoke(grant, actor, skip_revoke_notification: false, revoke_reason: nil)
    ProgrammaticAccessGrant::Service.revoke(grant, actor, skip_revoke_notification:, revoke_reason:)
  end

  def self.bulk_revoke(grant, actor, target, revoke_reason: nil)
    ProgrammaticAccessGrant::Service.bulk_revoke(grant, actor, target, revoke_reason:)
  end
end
