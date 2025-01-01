# typed: true
# frozen_string_literal: true

module HooksControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers
  include Kernel

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :sudo_filter, except: :index
    before_action :find_hook, only: [:show, :update, :destroy]
    before_action :ensure_hook_editable, only: [:update]

    helper_method :current_context
  end

  def index
    @hooks_view = Hooks::IndexView.new parent: current_context, current_user: current_user
    @preload_hook_statuses = current_user.feature_enabled?(:hooks_index_preload_hook_statuses)
    if params[:statuses]
      @hooks_view.load_hook_statuses
      respond_to do |format|
        format.html do
          render partial: "hooks/hooks_bucket", locals: { hooks_view: @hooks_view }
        end
      end
    else
      if @preload_hook_statuses
        @hooks_view.load_hook_statuses
      end
      render "hooks/index", locals: { hooks_view: @hooks_view, preload_hook_statuses: @preload_hook_statuses }
    end
  end

  def show
    if current_context.is_a?(Repository)
      @use_new_hooks_ui = user_feature_enabled?(:hooks_use_new_repo_hooks_ui)
    elsif current_context.is_a?(Organization)
      @use_new_hooks_ui = user_feature_enabled?(:hooks_use_new_org_hooks_ui)
    elsif current_context.is_a?(Business)
      @use_new_hooks_ui = user_feature_enabled?(:hooks_use_new_biz_hooks_ui)
    else
      @use_new_hooks_ui = false
    end
    tab = params[:tab]
    view = create_view_model(Hooks::ShowView, hook: @hook, use_new_hooks_ui: @use_new_hooks_ui)
    render "hooks/show", locals: { view: view, tab: tab }
  end

  def new
    @hook = if current_context.is_a?(Repository)
      Hook.new(installation_target: current_context, name: "web", active: true, events: default_events)
    else
      current_context.hooks.new name: "web", active: true, events: default_events
    end
    @hook_view = Hooks::ShowView.new hook: @hook, current_user: current_user
    render "hooks/new", locals: { hook: @hook, hook_view: @hook_view }
  end

  def create
    @hook = Hook.new name: "web", active: true, installation_target: current_context
    @hook.track_creator(current_user)

    if @hook.update(hook_params(@hook))
      flash[:notice] = hook_created_notification(@hook)
      redirect_to hooks_path(current_context)
    else
      @hook_view = Hooks::ShowView.new hook: @hook, current_user: current_user

      unless @hook.errors[:url].present?
        flash.now[:error] = "There was an error setting up your hook: #{@hook.errors.full_messages.to_sentence}"
      end
      render "hooks/new", locals: { hook_view: @hook_view, hook: @hook }
    end
  end

  def update
    params = hook_params(@hook)
    if params["partial_config"]
      @hook.update_existing_config(params["partial_config"])
      @hook.active = params["active"]
    else
      @hook.assign_attributes(params)
    end

    if @hook.save
      flash[:notice] = "Okay, the hook was successfully updated."
      redirect_to hook_path(@hook)
    else
      unless @hook.errors[:url].present?
        flash.now[:error] = "There was an error updating your hook: #{@hook.errors.full_messages.to_sentence}"
      end

      view = create_view_model(Hooks::ShowView, hook: @hook)
      render "hooks/show", locals: { view: view }
    end
  end

  def destroy
    @hook.destroy
    flash[:notice] = "Okay, that hook was successfully deleted."
    redirect_to hooks_path(current_context)
  end

  def update_pre_receive
    hook_id = params[:id]
    enforcement = params[:enforcement] # GitHub::PreReceiveHookEntry::ENABLED or GitHub::PreReceiveHookEntry::DISABLED
    final = params[:final].present?
    hookable_type = current_context.is_a?(Repository) ? "Repository" : "User"

    target = PreReceiveHookTarget.where(hook_id: hook_id, hookable_type: hookable_type, hookable_id: current_context.id).first
    if target
      target.update(enforcement: enforcement, final: final)
    else
      hook = PreReceiveHook.find_by(id: hook_id)
      target = T.must(hook).targets.create(enforcement: enforcement, hookable_type: hookable_type, hookable_id: current_context.id, final: final)
    end

    unless current_context.is_a?(Repository)
      final_message = final ? "and enforced on all repositories" : "and configurable on the repository level"
    end

    if target.enabled?
      flash[:notice] = "Hook is now enabled #{final_message}"
    else
      flash[:notice] = "Hook is now disabled #{final_message}"
    end

    redirect_to hooks_path(current_context)
  end

  private

  def default_events
    %w(push)
  end

  def hook_params(hook)
    return @hook_params unless @hook_params.nil?

    valid_fields = [:active, :url, :content_type, :insecure_ssl, :secret, events: []]

    @hook_params = params.require(:hook).permit(*valid_fields)
  end

  def find_hook
    @hook ||= begin
      if current_context.is_a?(::Repository)
        Hook.hooks_for_target(current_context).find_by(id: params[:id]).tap do |found_hook|
          raise ApplicationController::ErrorHandlingDependency::NotFound unless found_hook
        end
      else
        current_context.hooks.find_by_id(params[:id]).tap do |found_hook|
          raise ApplicationController::ErrorHandlingDependency::NotFound unless found_hook
        end
      end
    end
  end

  def ensure_hook_editable
    raise ApplicationController::ErrorHandlingDependency::NotFound unless @hook.editable_by?(current_user)
  end

  def hook_created_notification(hook)
    notice = "Okay, that hook was successfully created.".dup
    notice << " We sent a ping payload to test it out! Read more about it at #{GitHub.developer_help_url}/webhooks/#ping-event." if hook.webhook?
    notice
  end

  # Private: Returns the correct parent depending on if we're working
  # with org or repo hooks.
  #
  # Returns an Organization or a Repository
  def current_context
    raise NotImplementedError
  end
end
