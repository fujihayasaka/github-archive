# typed: true
# frozen_string_literal: true

class Businesses::OrgFilterMenuContentController < Businesses::BusinessController
  include BusinessesHelper

  before_action :login_required
  before_action :business_access_required
  before_action :business_owner_required
  before_action :supported_path_type_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: %i(show)

  def show
    respond_to do |format|
      format.any(:html, :html_fragment) do
        render partial: "businesses/people/org_filter_menu_content",
          layout: false, locals: { query: query_param, path_type: path_type_from_params }, formats: [:html, :html_fragment]
      end
    end
  end

  private

  def path_type_from_params
    params[:path_type].to_s.to_sym
  end

  def supported_path_types
    %i(members pending admins collaborators)
  end

  def supported_path_type_required
    render_404 unless supported_path_types.include?(path_type_from_params)
  end
end
