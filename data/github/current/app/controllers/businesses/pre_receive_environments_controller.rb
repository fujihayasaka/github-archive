# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveEnvironmentsController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :business_owner_required
  before_action :require_custom_pre_receive_hooks_enabled

  stylesheet_bundle :admin
  javascript_bundle :admin

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:environment_actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  def new
    @environment = PreReceiveEnvironment.new

    render "businesses/pre_receive_environments/new"
  end

  def create
    @environment = PreReceiveEnvironment.new(environment_params)

    if @environment.save
      flash[:notice] = "Successfully created environment"
      redirect_to enterprise_pre_receive_environments_path(GitHub.global_business)
    else
      render "businesses/pre_receive_environments/new"
    end
  end

  def index
    @environments = PreReceiveEnvironment.all

    render "businesses/pre_receive_environments/index"
  end

  def destroy
    @environment = PreReceiveEnvironment.find_by(id: params[:id])

    if !@environment || @environment.destroy
      flash[:notice] = "Successfully deleted environment"
    else
      error_message = @environment.errors[:base].to_sentence
      flash[:error] = "Error deleting environment. #{error_message}"
    end

  rescue ActiveRecord::DeleteRestrictionError
    flash[:error] = "Cannot delete environment that has hooks"
  ensure
    redirect_to enterprise_pre_receive_environments_path(GitHub.global_business)
  end

  def show
    @environment = PreReceiveEnvironment.find(params[:id])

    render "businesses/pre_receive_environments/show"
  end

  def update
    @environment = PreReceiveEnvironment.find(params[:id])

    if @environment.update(environment_params)
      flash[:notice] = "Successfully updated environment"
      redirect_to enterprise_pre_receive_environments_path(GitHub.global_business)
    else
      flash.now[:error] = @environment.errors[:base].to_sentence

      render "businesses/pre_receive_environments/show"
    end
  end

  def download # rubocop:todo GitHub/UseRestfulActions
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

  def environment_actions # rubocop:todo GitHub/UseRestfulActions
    @environment = PreReceiveEnvironment.find(params[:id])

    respond_to do |format|
      format.html do
        render partial: "businesses/pre_receive_environments/environment_actions", locals: { environment: @environment }
      end
    end
  end

  private

  def environment_params
    params.require(:pre_receive_environment).permit(:name, :image_url)
  end
end
