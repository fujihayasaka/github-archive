# typed: true
# frozen_string_literal: true

class Settings::WindbeamController < ApplicationController
  include Settings::ControllerMethods

  stylesheet_bundle :settings
  javascript_bundle :settings
  javascript_bundle :sessions

  before_action :sudo_filter, only: [:download]
  before_action :download_everything_button_feature_required
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Migrations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:download]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:download],
    optional: true

  def download # rubocop:todo GitHub/UseRestfulActions
    url = WindbeamExport.token_to_url(params[:token], current_user)

    if url.nil?
      GitHub.dogstats.increment "windbeam.export.download", tags: ["status:url_nil"]
      return render_404
    end

    GitHub.dogstats.increment "windbeam.export.download", tags: ["status:layout_rendered"]

    render "settings/migrations/download",
      locals: { redirect_url: url },
      layout: "layouts/redirect"
  end

  def download_everything_button_feature_required # rubocop:todo GitHub/UseRestfulActions
    render_404 unless GitHub.download_everything_button_enabled?
  end
end
