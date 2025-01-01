# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveHookTargetsController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :business_owner_required
  before_action :require_custom_pre_receive_hooks_enabled
  before_action :find_hook_target, only: [:show, :update, :destroy]
  before_action :require_hook_target, only: [:show, :update, :destroy]

  stylesheet_bundle :admin
  javascript_bundle :admin

  depends_on_clusters ApplicationRecord::Mysql1, only: [:new]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    render "businesses/pre_receive_hook_targets/show", locals: {
      view: Businesses::PreReceiveHookTargets::ShowPageView.new(selected_file: @target.hook.script, selected_repository_id: @target.hook.repository_id),
    }
  end

  def update
    hook = @target.hook
    PreReceiveHookTarget.transaction do
      begin
        hook.update! target_params[:hook_attributes]
        @target.update! target_params
        flash[:notice] = "Successfully updated hook"
        redirect_to hooks_enterprise_path(GitHub.global_business)
      rescue ActiveRecord::RecordInvalid
        flash.now[:error] = hook_error_message
        render "businesses/pre_receive_hook_targets/show", locals: {
          view: Businesses::PreReceiveHookTargets::ShowPageView.new(selected_file: @target.hook.script, selected_repository_id: @target.hook.repository_id),
        }
        raise ActiveRecord::Rollback
      end
    end
  end

  def new
    @target = PreReceiveHookTarget.new hook: PreReceiveHook.new(environment: PreReceiveEnvironment.default), enforcement: GitHub::PreReceiveHookEntry::ENABLED, final: true

    render "businesses/pre_receive_hook_targets/new", locals: {
      view: Businesses::PreReceiveHookTargets::ShowPageView.new,
    }
  end

  def create
    @hook = PreReceiveHook.new target_params[:hook_attributes]
    @target = PreReceiveHookTarget.new target_params.to_h.merge! hook: @hook, hookable: GitHub.global_business

    if @target.save
      flash[:notice] = "Successfully created hook"
      redirect_to hooks_enterprise_path(GitHub.global_business)
    else
      flash.now[:error] = hook_error_message

      render "businesses/pre_receive_hook_targets/new", locals: {
        view: Businesses::PreReceiveHookTargets::ShowPageView.new(
          selected_file: T.must(@target.hook).script,
          selected_repository_id: T.must(@target.hook).repository_id
        ),
      }
    end
  end

  def destroy
    if @target.hook.destroy
      flash[:notice] = "Successfully deleted hook"
      redirect_to hooks_enterprise_path(GitHub.global_business)
    else
      flash[:error] = "Error deleting hook"
      redirect_to hooks_enterprise_path(GitHub.global_business)
    end
  end

  private

  def find_hook_target # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @target ||= PreReceiveHookTarget.includes(:hook).find_by(id: params[:id], hookable: GitHub.global_business)
  end

  def require_hook_target
    return if @target

    flash[:error] = "Can not find hook"
    redirect_to hooks_enterprise_path(GitHub.global_business)
  end

  def target_params
    params.require(:pre_receive_hook_target).permit(
      :enforcement,
      :final,
      { hook_attributes: %i[name script repository_id environment_id] },
    )
  end

  def hook_error_message
    if @target.hook.errors.any?
      error_message = "Hook could not be saved."
      @target.hook.errors.full_messages.each do |msg|
        error_message = "#{error_message} #{msg}."
      end
      error_message
    end
  end
end
