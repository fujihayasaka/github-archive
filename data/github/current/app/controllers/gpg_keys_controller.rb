# typed: true
# frozen_string_literal: true

class GpgKeysController < ApplicationController
  before_action :login_required
  before_action :sudo_filter, only: ["create"]
  before_action :externally_managed_gpg_keys

  # The following actions do not require conditional access checks:
  # - create & destroy: these actions *don't* access protected organization resources
  skip_before_action :perform_conditional_access_checks, only: %w(create destroy) # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def create
    public_key = gpg_params[:public_key]
    name = gpg_params[:name]

    Failbot.push(public_key: public_key)
    @gpg_key = current_user.gpg_keys.create_from_armored_public_key(public_key, name: name, accept_revoked_keys: true)

    if @gpg_key.errors.any?
      flash[:error] = @gpg_key.errors.full_messages.to_sentence
    end

    bad_subkeys = @gpg_key.subkeys.filter { |s| s.errors.any? }
    if bad_subkeys.any?
      flash[:warn] = bad_subkeys.map { |s| s.errors.full_messages.to_sentence }.join(", ")
    end

    redirect_to settings_keys_path
  end

  def destroy
    find_key
    @gpg_key.destroy

    if request.xhr?
      head 200
    else
      flash[:notice] = "Okay, you have successfully deleted that key."
      redirect_to settings_keys_path
    end
  end

  private

  def gpg_params
    params.require(:gpg_key).permit(:name, :public_key)
  end

  def find_key
    @gpg_key = current_user.gpg_keys.primary_keys.find(params[:id])
  end

  def externally_managed_gpg_keys
    render_404 if GitHub.auth.gpg_keys_managed_externally?
  end
end
