# typed: true
# frozen_string_literal: true

class Orgs::RepositoryDefaultSettingsController < Orgs::Controller
  before_action :org_admins_only

  before_action :ensure_trade_restrictions_allows_org_settings_access

  before_action { @selected_link = :repo_defaults }

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  LABELS_PER_PAGE = 30

  def index
    labels = current_organization.user_labels
      .order(:lowercase_name)
      .paginate(per_page: LABELS_PER_PAGE, page: current_page)
    new_label = current_organization.user_labels.new(color: UserLabel.defaults.sample.color)

    render "orgs/repository_default_settings/index", locals: { labels: labels, new_label: new_label }
  end
end
