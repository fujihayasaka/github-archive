# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::ReputableOrgsPartialsController < Stafftools::SponsorsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:show]

  REPUTABLE_ORGS_PER_PAGE = 10

  def show
    render partial: "stafftools/sponsors/members/criteria/member_reputable_org/organizations",
      locals: { sponsorable: this_sponsorable }
  end
end
