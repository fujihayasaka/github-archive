# typed: true
# frozen_string_literal: true

class Organization::InvalidInviteStatus < Organization::InviteStatus
  def initialize; end
  def present?; false; end
  def blank?; true; end
  def nil?; true; end

  def errors
    %i(invitee_or_email_required)
  end
end
