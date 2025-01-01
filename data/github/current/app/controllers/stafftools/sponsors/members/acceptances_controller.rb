# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::AcceptancesController < Stafftools::SponsorsController
  def create
    result = Sponsors::AcceptSponsorsMembership.call(sponsorable: this_sponsorable,
      actor: current_user)

    if result.success?
      email_time_in_minutes = SponsorsListing::StateDependency::EMAIL_WAIT_TIME.to_i / 60
      flash[:notice] = "Successfully accepted Sponsors membership for #{this_sponsorable}, " \
        "scheduling an acceptance email to be sent to the user in #{email_time_in_minutes} " \
        "minutes. If you undo acceptance before then, it will cancel the scheduled email."
    else
      flash[:error] = "An error occurred when accepting the Sponsors membership for " \
        "#{this_sponsorable}: #{result.errors.to_sentence}"
    end

    redirect_to stafftools_sponsors_waitlist_queue_index_path(after: this_listing.id)
  end

  def destroy
    if !this_listing.waitlisted? && !this_listing.can_revert_to_waitlisted?
      flash[:error] = "#{this_sponsorable}'s Sponsors listing cannot be reverted back " \
        "to waitlisted."
      return redirect_to(stafftools_sponsors_member_path(this_sponsorable))
    end

    success = this_listing.waitlisted? || this_listing.revert_to_waitlisted!

    if success
      flash[:notice] = "Successfully reverted Sponsors listing for #{this_sponsorable} " \
        "to waitlisted."
    else
      reason = this_listing.halted_because
      flash[:error] = "An error occurred when reverting the Sponsors listing for " \
        "#{this_sponsorable} to waitlisted: #{reason}"
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
