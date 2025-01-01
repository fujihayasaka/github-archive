# typed: true
# frozen_string_literal: true

class Biztools::CustomSignupContentController < BiztoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  before_action :dotcom_required

  def index
    render "biztools/custom_signup_content/index", locals: { pages: pages }
  end

  private

  def pages
    YAML.safe_load_file("app/components/signups/data/signups_content_panel_data.yml", aliases: true)
      .fetch("pages", [])
  end
end
