# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveEnvironmentDownloadsController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :business_owner_required
  before_action :require_custom_pre_receive_hooks_enabled

  def create
    @environment = PreReceiveEnvironment.find(params[:id])
    if @environment.default_environment?
      flash[:notice] = "Default environment can't be modified"
    elsif @environment.download_in_progress?
      flash[:notice] = "Download is already in progress"
    else
      @environment.queue_download
    end
    redirect_to enterprise_pre_receive_environments_path(GitHub.global_business)
  end
end
