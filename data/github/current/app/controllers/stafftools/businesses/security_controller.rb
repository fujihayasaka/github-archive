# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SecurityController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
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

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    ip_allowlist_entries = this_business.ip_allowlist_entries
      .for_query(params[:query])
      .order(allow_list_value: :asc)
      .paginate(page: params[:page])
    render "stafftools/businesses/security", locals: {
      ip_allowlist_entries: ip_allowlist_entries
    }
  end
end
