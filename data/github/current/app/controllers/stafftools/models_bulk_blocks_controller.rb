# typed: true
# frozen_string_literal: true

class Stafftools::ModelsBulkBlocksController < StafftoolsController
  before_action :dotcom_required

  def create
    logins = params[:logins]
      .split(/[,\s]+/) # support both comma and space-delimited strings
      .map { |login| login.gsub(/\A['"]|['"]\Z/, "") } # strip surrounding quotes

    users = User.where(login: logins)

    logins_without_users = logins - users.map(&:login)
    if logins_without_users.any?
      flash[:error] = "Could not find users with logins: #{logins_without_users.join(", ")}"
    end

    users.each do |user|
      GitHubModels::Block.block!(
        actor: current_user,
        user: user,
        reason: "#{params[:reason]} #{params[:additional_information]}".strip,
      )
    end

    flash[:notice] = "Attempted to block #{users.count} users."

    redirect_to stafftools_models_path
  end
end
