# typed: true
# frozen_string_literal: true

class Devtools::Spamurai::DatasourcesController < DevtoolsController
  before_action :login_required
  before_action :sudo_filter

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index],
    optional: true

  def index
    render "devtools/spamurai/datasources/index",
      locals: {
      spam_datasources: SpamDatasource.all.paginate(page: current_page),
    }
  end

  def show
    spam_datasource = SpamDatasource.find(params[:id])
    entries = spam_datasource.entries.paginate page: current_page
    render "devtools/spamurai/datasources/show", locals: {
      spam_datasource: spam_datasource,
      entries: entries,
    }
  end

  private

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil,
      label: "Datasources",
      path: spamurai_datasources_path,
      parent: ContextRegion::Devtools::SpamuraiCrumb.new
    )
  end
end
