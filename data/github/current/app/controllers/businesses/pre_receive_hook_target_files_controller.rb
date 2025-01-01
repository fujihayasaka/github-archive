# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveHookTargetFilesController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :business_owner_required
  before_action :require_custom_pre_receive_hooks_enabled

  stylesheet_bundle :admin
  javascript_bundle :admin

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  def index
    respond_to do |f|
      f.html do
        render partial: "businesses/pre_receive_hook_targets/files",
          locals: {
            view: create_view_model(Businesses::PreReceiveHookTargets::ShowPageView,
              selected_file: params[:file],
              selected_repository_id: params[:repository_id]
            )
          }
      end
    end
  end
end
