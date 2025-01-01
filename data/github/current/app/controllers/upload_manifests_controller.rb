# typed: true
# frozen_string_literal: true

class UploadManifestsController < ApplicationController

  before_action :login_required

  def create
    return render_404 unless current_repository.pushable_by?(current_user)

    directory =
      if params[:directory_binary]
        Base64.decode64(params[:directory_binary])
      end

    manifest = UploadManifest.new(
      repository: current_repository,
      uploader: current_user,
      directory: directory)

    if manifest.save
      render status: 201, json: manifest.as_json(only: :id)
    else
      render status => 422, :json => { errors: manifest.errors.full_messages }
    end
  end

  private

  def current_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_repository if defined?(@current_repository)
    @current_repository = Repositories::Public.find_active!(params[:repository_id])
  end

  def target_for_conditional_access
    # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    return :no_target_for_conditional_access unless current_repository
    # rubocop:enable GitHub/SpecifyTargetForConditionalAccess
    current_repository.owner
  end
end
