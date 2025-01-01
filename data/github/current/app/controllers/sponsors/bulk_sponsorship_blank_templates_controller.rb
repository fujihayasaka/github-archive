# typed: true
# frozen_string_literal: true

class Sponsors::BulkSponsorshipBlankTemplatesController < ApplicationController
  include Sponsors::SharedDependenciesControllerMethods

  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab, ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories

  def index
    send_data(
      Sponsors::BulkSponsorshipBlankTemplate.to_csv,
      filename: Sponsors::BulkSponsorshipBlankTemplate.filename,
      type: "text/csv"
    )
  end
end
