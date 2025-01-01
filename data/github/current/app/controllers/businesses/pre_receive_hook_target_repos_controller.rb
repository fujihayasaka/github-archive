# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveHookTargetReposController < Businesses::BusinessController
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
      f.html_fragment do
        render partial: "businesses/pre_receive_hook_targets/repo_results",
          formats: :html,
          locals: {
            view: create_view_model(Businesses::PreReceiveHookTargets::ShowPageView, query: params[:query])
          }
      end
    end
  end
end
