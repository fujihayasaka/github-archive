# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::PotentialSponsorsController < StafftoolsController
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  # Returns rendered HTML list items used for autocompletion support
  def index
    potential_sponsors = User.search(params[:q], with_orgs: true, exclude_suspended: true)
    potential_sponsorable_id = params[:potential_sponsorable_id].to_i
    if potential_sponsorable_id
      potential_sponsors.reject! { |potential_sponsor| potential_sponsor.id == potential_sponsorable_id }
    end
    GitHub::PrefillAssociations.prefill_associations(potential_sponsors, :profile)
    render "stafftools/sponsors/potential_sponsors/index", formats: :html, layout: false, locals: {
      potential_sponsors: potential_sponsors,
    }
  end
end
