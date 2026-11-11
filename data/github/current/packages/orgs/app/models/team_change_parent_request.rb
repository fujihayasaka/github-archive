# typed: true
# frozen_string_literal: true

class TeamChangeParentRequest < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification

  # Raised when attempting to approve or cancel an already-approved request.
  class AlreadyApprovedError < StandardError
  end

  # Have to give more explicit names here. Just doing `parent` crashes on load because
  # it would shadow the `parent` attribute in the underlying table
  enum :requesting_team_type, { child_request: 0, parent_request: 1 }

  belongs_to :parent_team, class_name: "Team"
  belongs_to :child_team, class_name: "Team"
  belongs_to :approved_by, class_name: "User"
  belongs_to :requester, class_name: "User"

  # Requests from potential parents to a given team (parent-initiated request)
  scope :inbound_parent_initiated, ->(team) {
    parent_request.where(child_team_id: team.id)
  }

  # Requests to potential children from a given team (parent-initiated request)
  scope :outbound_parent_initiated, ->(team) {
    parent_request.where(parent_team_id: team.id)
  }

  # Requests to potential parents from a given team (child-initiated request)
  scope :inbound_child_initiated, ->(team) {
    child_request.where(parent_team_id: team.id)
  }

  # Requests from potential children to a given team (child-initiated request)
  scope :outbound_child_initiated, ->(team) {
    child_request.where(child_team_id: team.id)
  }

  # Orders by either the parent team name or child team name based on what is sent in for field
  scope :order_by_team_name, ->(field) {
    joins(field).order("teams.name ASC")
  }

  # Returns all requests that have the same child_team and parent_team as the one passed in
  scope :identical_to, ->(parent_team_id, child_team_id, request_id = nil) {
    scope = where(parent_team_id: parent_team_id, child_team_id: child_team_id)

    request_id ? scope.where("id != ?", request_id) : scope
  }

  # Returns circular requests involving a parent/child of the request passed in and any ancestor or descendant teams
  scope :circular_to, ->(req) {
    team_ids = req.parent_team.ancestor_and_descendant_ids |
               req.child_team.ancestor_and_descendant_ids

    as_parents = where(parent_team_id: [req.parent_team_id, req.child_team_id], child_team_id: team_ids).pending.pluck(:id)
    as_children = where(parent_team_id: team_ids, child_team_id: [req.parent_team_id, req.child_team_id]).pending.pluck(:id)

    where(id: as_parents + as_children)
  }

  scope :involving, ->(team) {
    t = arel_table
    where(
      t[:parent_team_id].eq(team.id).or(t[:child_team_id].eq(team.id)),
    )
  }

  scope :pending, -> { where(approved_at: nil) }

  validates_presence_of :parent_team_id, :child_team_id, :requester_id
  validates_uniqueness_of :parent_team_id, scope: [:child_team_id, :requesting_team_type, :approved_at]
  before_validation :set_default_requesting_team_type
  validates :requesting_team_type, presence: true
  validate :validate_parent_not_secret, :validate_child_not_secret, :validate_teams_in_same_org

  after_create :seek_approval_for_request, :instrument_request_to_move_team

  # Public: create a request with the parent team as the requesting team.
  #
  # args:   Hash of arguments passed to the ActiveRecord create method.
  #
  # Returns a TeamChangeParentRequest when successful. Raises if not.
  def self.create_initiated_by_parent!(args = {})
    create!(args.merge(requesting_team_type: :parent_request))
  end

  # Public: create a request with the child team as the requesting team.
  #
  # args:   Hash of arguments passed to the ActiveRecord create method.
  #
  # Returns a TeamChangeParentRequest when successful. Raises if not.
  def self.create_initiated_by_child!(args = {})
    create!(args.merge(requesting_team_type: :child_request))
  end

  # Public: Approves the change parent request.
  #
  # actor: User approving the request.
  #
  # Raises TeamChangeParentRequest::AlreadyApprovedError (a StandardError) if
  # the request has already been approved.
  #
  # Returns nothing.
  def approve(actor:)
    raise AlreadyApprovedError, "this request has already been approved" if approved?

    update!(
      approved_at: Time.zone.now,
      approved_by: actor,
    )

    Team::Editor.update_team(child_team, parent_team_id: T.must(parent_team).id)
  rescue Team::ParentChange::CannotAcquireLockError
    # do nothing, silently pass through.
  end

  # Public: Cancel the request.
  #
  # actor - The user canceling the request.
  #
  # Returns nothing.
  def cancel(actor:)
    raise AlreadyApprovedError, "can't cancel an approved invitation" if approved?

    T.must(parent_team).instrument(:cancel_child_team_request,
      actor: actor,
      requester: requester,
    )

    destroy
  end

  # Public: Has the request been approved?
  #
  # Returns a boolean.
  def approved?
    approved_at?
  end

  # Public: Is the request pending?
  #
  # Returns a boolean.
  def pending?
    !approved?
  end

  # Public: the Team that initiated this request.
  #
  # Returns a Team.
  def requesting_team
    case
    when parent_request? then parent_team
    when child_request? then child_team
    end
  end

  # Public: the Team that must approve this request.
  #
  # Returns a Team.
  def requested_team
    case
    when parent_request? then child_team
    when child_request? then parent_team
    end
  end

  # Public: Async version of #requested_team.
  #
  # Returns a Promise that resolves to a Team.
  def async_requested_team
    Promise.all([async_parent_team, async_child_team]).then do
      requested_team
    end
  end

  def self.cleanup_duplicates_to(request, actor)
    requests_to_cancel = identical_to(request.parent_team_id, request.child_team_id, request.id).pending
    requests_to_cancel += circular_to(request).pending

    requests_to_cancel.each do |request|
      request.cancel(actor: actor)
    end
  end

  # Retrieves pending requests from potential parents to a given team
  def self.inbound_pending_requests_non_null_parent_initiated(team)
    self.inbound_parent_initiated(team).pending.select { |request| request.requesting_team.present? }
  end

  # Retrieves pending requests to potential parents from a given team (child-initiated)
  def self.inbound_pending_requests_non_null_child_initiated(team)
    self.inbound_child_initiated(team).pending.select { |request| request.requesting_team.present? }
  end

  private

  # Internal
  def set_default_requesting_team_type
    requesting_team_type = :child if requesting_team_type.blank?
  end

  # Internal: send the notificantion mailer.
  #
  # Returns nothing.
  def seek_approval_for_request
    TeamsMailer.team_relationship_request(requester: requester, parent_team: parent_team, child_team: child_team, initiated_by_parent: parent_request?).deliver_later
  end

  # Internal: instrument the request to move the team.
  #
  # Returns nothing.
  def instrument_request_to_move_team
    GitHub.dogstats.increment("team.team_relationship_request", tags: ["action:request"])

    requesting_team.instrument(:team_relationship_request,
      requester: requester,
    )
  end

  # Internal: Validate that a parent is not secret
  def validate_parent_not_secret
    if parent_team&.secret?
      errors.add :parent_team_id, "can't be a secret team"
    end
  end

  # Internal: Validate that a child is not secret
  def validate_child_not_secret
    if child_team&.secret?
      errors.add :child_team_id, "can't be a secret team"
    end
  end

  # Internal: Validate that the parent team and child team are in the same organization
  def validate_teams_in_same_org
    if parent_team&.organization != child_team&.organization
      errors.add :organization, "parent team and child team must be in the same organization"
    end
  end
end
