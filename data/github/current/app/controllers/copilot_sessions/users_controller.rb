# typed: true
# frozen_string_literal: true

class CopilotSessions::UsersController < ApplicationController
  before_action :reject_enterprise
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,

  def index
    user_ids = params[:user_ids].split(",").map(&:to_i) || []
    users = User.where(id: user_ids).map { |user| ::CopilotSessions::Payloads::PublicUser.new(user).call }
    respond_to do |format|
      format.json do
        render json: {
          users: users
        }
      end
    end
  end

  private

  def target_for_conditional_access
    current_user
  end

  def reject_enterprise
    render_404 if GitHub.enterprise?
  end
end
