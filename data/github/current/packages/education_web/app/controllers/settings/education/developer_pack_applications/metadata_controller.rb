# typed: strict
# frozen_string_literal: true

class Settings::Education::DeveloperPackApplications::MetadataController < ApplicationController
  include Settings::ControllerMethods
  include Settings::Education::DeveloperPackApplications::SharedControllerMethods

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    only: [:show],
  )

  sig { void }
  def show
    return render_404 unless metadata_record.present?

    render(
      Education::DeveloperPackApplication::MetadataComponent.new(metadata_record: T.must(metadata_record)),
      layout: false,
    )
  end

  private

  sig { returns(T.nilable(EducationDeveloperPackApplicationMetadata)) }
  memoize def metadata_record
    current_user.developer_pack_application_metadata.find(params[:id])
  end
end
