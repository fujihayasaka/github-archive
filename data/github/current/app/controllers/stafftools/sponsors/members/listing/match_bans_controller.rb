# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Listing::MatchBansController < Stafftools::SponsorsController
  def create
    if sponsor = User.find_by(login: params[:sponsor_login])
      result = SponsorshipMatchBan.create_for(
        sponsorable: this_sponsorable,
        sponsor: sponsor,
        actor: current_user,
      )

      if result.success?
        flash[:notice] = "Disabled matching sponsorships for #{this_sponsorable} from #{sponsor}."
      else
        flash[:error] = result.errors.to_sentence
      end
    else
      flash[:error] = "Could not find account with login #{params[:sponsor_login]}."
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  def destroy
    match_ban = this_sponsorable.sponsorship_match_bans_as_sponsorable.find(params[:id])
    result = match_ban.unban(actor: current_user)

    if result.success?
      flash[:notice] = "Enabled matching sponsorships for #{this_sponsorable} from #{match_ban.sponsor}."
    else
      flash[:error] = result.errors.to_sentence
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
