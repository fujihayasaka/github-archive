# typed: true
# frozen_string_literal: true

class Stafftools::CustomPropertiesController < StafftoolsController
  include ReactHelper

  before_action -> do
    T.bind(self, Stafftools::CustomPropertiesController)
    render_404 unless current_repository&.owner&.organization?
  end
  before_action :ensure_repo_exists

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::Mysql5,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Billing,
  ApplicationRecord::Spokes,
  ApplicationRecord::Ballast,
  only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def self.react_bundle_name
    "stafftools-custom-properties"
  end

  def index
    properties = CustomProperties::Public.repo_properties([current_repository], :effective)[current_repository]
    return render_404 if properties.nil?

    render_react_app(
      title: "Properties",
      payload: { properties: properties },
      page_data: {
        selected_link: :custom_properties
      },
      layout: "layouts/stafftools/repository/overview",
      ssr: false
    )
  end
end
