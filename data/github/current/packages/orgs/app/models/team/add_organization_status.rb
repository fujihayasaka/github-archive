# typed: true
# frozen_string_literal: true

# Public: A response is created when a user is added to a team.
class Team::AddOrganizationStatus
  MESSAGES = {
    no_seat: "There are not enough available seats in this enterprise for all the team members.",
    pending_cycle_no_seat: "There are not enough available seats in this enterprise for all the team members during the pending cycle.",
  }

  # Public: A Symbol. :success, :no_seat, :pending_cycle_no_seat.
  attr_reader :status

  def initialize(status)
    @status = status
    freeze
  end

  private :initialize

  # Public: Did an error occur while adding a member?
  def error?
    !success?
  end

  # Public: Was a member successfully added?
  def success?
    status == :success
  end

  # Public: Describe the error if any.
  def message
    MESSAGES[status]
  end

  # Public: Org isn't permitted to be added because there isn't enough seats for all the business team members.
  NO_SEAT = new(:no_seat)

  # Public: Org isn't permitted to be added because there will not be enough available seats after the business pending downgrade.
  PENDING_CYCLE_NO_SEAT = new(:pending_cycle_no_seat)

  # Public: orgs were successfully added (up to the limit, no effect if selection type is all or unknown orgs).
  SUCCESS = new(:success)
end
