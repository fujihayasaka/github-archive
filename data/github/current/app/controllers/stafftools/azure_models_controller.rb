# typed: true
# frozen_string_literal: true

class Stafftools::AzureModelsController < StafftoolsController
  include Marketplace::Models::PlaygroundDependency

  layout "layouts/stafftools/user/content"

  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    render "stafftools/models/show", locals: {
      user: this_user,
      blocks: AzureModels::Block.where(user: this_user).order(created_at: :desc),
      blocked: AzureModels::Block.blocked?(this_user),
      access_result: check_playground_access(user: this_user),
      auths_count: AzureModels::UsageDetails.auths_count_for_user_id(this_user.id)
    }
  end

  def block # rubocop:todo GitHub/UseRestfulActions
    if params[:user_block_action] == "allow"
      AzureModels::Block.unblock!(actor: current_user, user: this_user, reason: params[:reason])
    elsif params[:user_block_action] == "block"
      AzureModels::Block.block!(
        actor: current_user,
        user: this_user,
        reason: "#{params[:reason]} #{params[:additional_information]}".strip,
      )
    end
    redirect_to stafftools_user_azure_models_path(this_user.display_login)
  end
end
