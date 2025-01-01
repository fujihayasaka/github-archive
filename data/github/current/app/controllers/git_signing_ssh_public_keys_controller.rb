# typed: true
# frozen_string_literal: true

class GitSigningSshPublicKeysController < ApplicationController
  before_action :login_required
  before_action :find_key

  def destroy
    @git_signing_key.destroy_with_explanation(:removed_by_user)
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

  private

  def key_type
    "git_signing_key"
  end

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def html_redirect
    redirect_to settings_keys_path
  end

  def find_key
    @git_signing_key = current_user.git_signing_ssh_public_keys.find(params[:id])
  end
end
