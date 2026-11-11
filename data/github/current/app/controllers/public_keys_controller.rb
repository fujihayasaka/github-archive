# typed: true
# frozen_string_literal: true

class PublicKeysController < ApplicationController
  before_action :login_required
  before_action :parent_object_exists
  before_action :sudo_filter, only: ["create"]
  before_action :externally_managed_ssh_keys

  def create
    public_key_data = public_key_params
    read_only = public_key_data[:read_only] == "1"

    @public_key = parent_object.public_keys.create_with_verification \
      key: public_key_data[:key],
      title: public_key_data[:title],
      read_only: read_only,
      verifier: current_user

    if @public_key.new_record?
      flash[:error] = @public_key.errors.full_messages.to_sentence
    end

    html_redirect
  end

  def destroy
    find_key
    @public_key.destroy_with_explanation(:removed_by_user)
    key_type = "public_key"
    GitHub.dogstats.increment(key_type, tags: ["action:destroy", "valid:true"])

    if request.xhr?
      head :ok
    else
      flash[:notice] = "Okay, you have successfully deleted that key."
      html_redirect
    end
  rescue ActiveRecord::RecordInvalid
    GitHub.dogstats.increment(key_type, tags: ["action:destroy", "valid:false"])
    if request.xhr?
      head :bad_request
    else
      flash[:error] = "There was an error deleting the key"
      html_redirect
    end
  end

  def verify # rubocop:todo GitHub/UseRestfulActions
    find_key

    if @public_key.verify(current_user)
      GitHub.dogstats.increment("public_key", tags: ["action:verify", "valid:true"])

      if request.xhr?
        head 200
      else
        flash[:notice] = "Okay, you’ve successfully approved that SSH key."
        html_redirect
      end
    else
      GitHub.dogstats.increment("public_key", tags: ["action:verify", "valid:false"])

      if request.xhr?
        head 422
      else
        flash[:error] = "We had a problem approving your key. Please try "     \
          "again. If you continue to experience this issue, "   \
          "#{GitHub.support_link_text_lowercase}."

        html_redirect
      end
    end
  end

  def remove_authorization # rubocop:todo GitHub/UseRestfulActions
    org = Organization.find_by_login(params[:org])

    authorization = Organization::CredentialAuthorization.authorization \
      organization: org, credential: find_key
    return render_404 unless authorization

    authorization.destroy

    flash[:notice] = "The public key is no longer authorized to access #{ org }."
    html_redirect
  end

  private

  # CAP bypass is fine as login_required
  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_repository # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_repository.owner
  end

  def html_redirect
    if params[:repository]
      redirect_to repository_keys_path(current_repository.owner, current_repository)
    else
      redirect_to settings_keys_path
    end
  end

  def parent_object # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @parent_object ||= if params[:repository]
      current_repository
    else
      current_user
    end
  end

  def parent_object_exists
    case parent_object
    when User
    when Repository
      render_404 unless parent_object.async_can_manage_deploy_keys?(current_user).sync
    else render_404
    end
  end

  def find_key
    @public_key = parent_object.public_keys.find(params[:id])
  end

  def current_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_repository if defined?(@current_repository)
    @current_repository = owner.find_repo_by_name(params[:repository]) if owner
  end

  def owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @owner ||= User.find_by_login(params[:user_id]) if params[:user_id]
  end

  def externally_managed_ssh_keys
    render_404 if GitHub.auth.ssh_keys_managed_externally? && !current_repository
  end

  def public_key_params
    params.require(:public_key).permit %i[title key read_only]
  end
end
