# typed: true
# frozen_string_literal: true
class Stafftools::EmailClaimsController < StafftoolsController
  before_action :check_user, only: [:create, :update]

  def create
    primary_email = this_user.primary_user_email
    if primary_email.request_claim(requested_by: this_user)
      flash[:notice] = "Confirmation to claim primary email has been resent to #{primary_email.deobfuscated_email}."
    else
      flash[:error] = "Failed to resend confirmation to claim primary email #{primary_email.deobfuscated_email}."
    end
    redirect_to :back
  end

  def update
    primary_email = this_user.primary_user_email

    if primary_email.update(claimed: false)
      instrument("staff.#unclaimed_primary_email", user: this_user)
      redirect_to :back, flash: { notice: "Primary email #{primary_email.deobfuscated_email} unclaimed successfully." }
    else
      redirect_to :back, flash: { error: "Failed to unclaim primary email #{primary_email.deobfuscated_email}." }
    end
  end

  private

  def check_user
    unless this_user.is_enterprise_managed?
      redirect_to :back, flash: { error: "User is not enterprise managed." }
    end
  end
end
