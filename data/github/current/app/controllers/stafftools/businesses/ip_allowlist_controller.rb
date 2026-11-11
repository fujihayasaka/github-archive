# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::IpAllowlistController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    render "stafftools/businesses/ip_allowlist/show", locals: {
      ip_allowlist_entries: ip_allowlist_entries
    }
  end

  private

  memoize def ip_allowlist_entries
    this_business
      .ip_allowlist_entries
      .for_query(params[:query])
      .order(allow_list_value: :asc)
      .paginate(page: params[:page])
  end
end
