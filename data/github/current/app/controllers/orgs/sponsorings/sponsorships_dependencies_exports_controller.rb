# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::SponsorshipsDependenciesExportsController < Orgs::Controller
  extend T::Sig

  include ApplicationController::JsonDependency
  include Sponsors::SharedControllerMethods
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:create]

  before_action :sponsors_required
  before_action :viewer_can_manage_sponsorships
  before_action :parse_json_params

  sig { void }
  def create
    ExportSponsorsDependenciesJob.perform_later(
      org: this_organization,
      actor: current_user,
    )

    render(
      json: {
        msg: "You've started an export of your organization's dependencies. " \
        "You'll receive an email at #{current_user.email} with the export attached.",
      },
      status: 200,
    )
  end

  private

  sig { void }
  def viewer_can_manage_sponsorships
    render_404 if current_user.potential_sponsor_ids.exclude?(this_organization.id)
  end
end
