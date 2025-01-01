# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module ProgrammaticAccessGrantRequest
  ORGANIZATION_TYPE = OrganizationProgrammaticAccessGrantRequest

  def self.is_request?(grant_requestable)
    grant_requestable.instance_of?(OrganizationProgrammaticAccessGrantRequest) || \
      grant_requestable.instance_of?(UserProgrammaticAccessGrantRequest)
  end

  def self.preview_reason(target, text)
    "#{target.class.name}ProgrammaticAccessGrantRequest".constantize.new(
      target: target, reason: text
    )
  end

  def self.with_repository(repository)
    params = { repository: repository }
    ProgrammaticAccessGrantRequest::Finder.new(params: params).perform
  end

  def self.with_repository_and_grant_request_owner(repository, grant_request_owner)
    params = { repository: repository, owner: grant_request_owner }
    ProgrammaticAccessGrantRequest::Finder.new(params: params).perform
  end

  def self.with_target(target)
    params = { target: target }
    case target
    when Organization
      ProgrammaticAccessGrantRequest::Finder.new(params: params).perform
    when User
      ProgrammaticAccessGrantRequest::Finder.new(params: params).perform
    else
      OrganizationProgrammaticAccessGrantRequest.none
    end
  end

  def self.with_target_and_access(target, access)
    with_target(target).find_by(user_programmatic_access: access)
  end

  def self.with_target_type_and_access(target_type, access)
    params = { target_type: target_type, access: access }
    ProgrammaticAccessGrantRequest::Finder.new(params: params).perform
  end

  def self.with_target_and_owner(target, owner)
    params = { target: target, owner: owner }
    ProgrammaticAccessGrantRequest::Finder.new(params: params).perform
  end

  # Public:  Finds *ProgrammaticAccessGrantRequest records for a given target
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
  # Returns a scope of *ProgrammaticAccessGrantRequest records
  def self.with_target_and_filters(target, filters)
    return ProgrammaticAccessGrantRequest.none if target.nil?

    params = filters.merge({ target: target })
    ProgrammaticAccessGrantRequest::Finder.new(params: params).perform
  end

  def self.from_target_and_id(target, id)
    with_target(target).find_by(id: id)
  end

  def self.from_target_and_ids(target, ids)
    with_target(target).where(id: ids)
  end

  def self.create(attributes = {})
    ProgrammaticAccessGrantRequest::Service.create(attributes)
  end

  def self.approve(request, actor, skip_approval_notification: false, entry_point:)
    ProgrammaticAccessGrantRequest::Service.approve(request, actor, skip_approval_notification: skip_approval_notification, entry_point: entry_point)
  end

  def self.bulk_approve(requests, actor, target, entry_point:)
    ProgrammaticAccessGrantRequest::Service.bulk_approve(requests, actor, target, entry_point: entry_point)
  end

  def self.deny(request, actor, reason = nil)
    ProgrammaticAccessGrantRequest::Service.deny(request, actor, reason)
  end

  def self.bulk_deny(requests, actor, target)
    ProgrammaticAccessGrantRequest::Service.bulk_deny(requests, actor, target)
  end

  def self.cancel(request, actor)
    ProgrammaticAccessGrantRequest::Service.cancel(request, actor)
  end

  def self.targeted_organization_ids(next_id: nil)
    orgs_with_requests = OrganizationProgrammaticAccessGrantRequest.distinct.order(organization_id: :asc)
    orgs_with_requests = orgs_with_requests.where("organization_id >= ?", next_id) if next_id

    orgs_with_requests.pluck(:organization_id)
  end

  def self.accessible_repository_ids_on_by(target, actor)
    ProgrammaticAccessGrantRequest::Service.accessible_repository_ids_on_by(target, actor)
  end

  def self.approvable_by?(target, actor)
    emphemeral_grant_request =
      case target
      when Organization
        OrganizationProgrammaticAccessGrantRequest.new(target: target)
      when User
        UserProgrammaticAccessGrantRequest.new(target: target)
      end

    return false unless emphemeral_grant_request.present?

    emphemeral_grant_request.approvable_by?(actor)
  end

  def self.none
    OrganizationProgrammaticAccessGrantRequest.none
  end
end
