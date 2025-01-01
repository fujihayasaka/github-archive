# typed: true
# frozen_string_literal: true

class TeamMembershipRequest < ApplicationRecord::Domain::Users
  # Raised when someone approves an already-approved request.
  class AlreadyApprovedError < StandardError
  end

  belongs_to :requester, class_name: "User"
  belongs_to :team

  validates_presence_of :team_id, :requester_id
  validates_uniqueness_of :requester_id, scope: [:team_id, :approved_at]

  after_commit :seek_approval_for_request, :instrument_request_to_join_team, on: :create

  # Excludes records where the requester is a spammy user unless the viewer is
  # staff.
  #
  #
  # viewer - The User we are rendering the records for.
  #          Usually should be current_user. Accomodates viewer
  #          being nil/false for anonymous users.
  # show_spam_to_staff - Override the assumption that staff should
  #                      see spam by setting this to `false`.
  #                      Defaults to `true`.
  scope :filter_spam_for, lambda { |viewer, show_spam_to_staff: true|
    return unless GitHub.spamminess_check_enabled?

    # We don't filter anything for staff
    return if viewer.try(:site_admin?) && show_spam_to_staff

    request = arel_table
    user = User.arel_table

    joins(request.join(user, Arel::Nodes::OuterJoin).on(request[:requester_id].eq(user[:id])).join_sources)
      .where(user[:spammy].eq(false))
  }

  # Public: Approve the invitation. This adds the invitee to the specified team
  # and marks the request as approved
  #
  # actor - The user approving the request.
  #
  # Returns nothing.
  def approve(actor:)
    raise AlreadyApprovedError, "request already approved" if approved?

    GitHub.dogstats.distribution("team.team_membership_requests.dist.seconds_between_request_and_approve", Integer(Time.now.to_i - created_at.to_i))

    add_member_status = T.must(team).add_member(requester, adder: actor)

    if add_member_status && add_member_status.error?
      raise
    else
      T.must(team).instrument(:approve_team_membership_request,
        actor: actor,
        requester: requester,
      )

      touch :approved_at
    end
  end

  # Public: Cancel the invitation.
  #
  # actor - The user canceling the request.
  #
  # Returns nothing.
  def cancel(actor:)
    raise AlreadyApprovedError, "can't cancel an approved invitation" if approved?

    T.must(team).instrument(:cancel_team_membership_request,
      actor: actor,
      requester: requester,
    )

    GitHub.dogstats.increment("team_membership_request", tags: ["action:cancel"])

    destroy
  end

  # Public: Has the invitation been approved?
  #
  # Returns a boolean.
  def approved?
    approved_at.present?
  end

  private

  def seek_approval_for_request
    TeamsMailer.team_membership_request(requester: requester, team: team).deliver_later
  end

  def instrument_request_to_join_team
    GitHub.dogstats.increment("team_membership_request", tags: ["action:request"])

    T.must(team).instrument(:team_membership_request,
      requester: requester,
    )
  end
end
