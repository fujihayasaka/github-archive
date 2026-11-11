# typed: true
# frozen_string_literal: true

class Settings::Keys::SshKeysController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :sudo_filter, only: [:create]

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  def new
    @selected_link = :ssh_keys
    render "settings/keys/ssh_keys/new"
  end

  # intended to let a user create a new SSH key,
  # either a public (authoring) key or a signing key. This form is not
  # intended to work with repository keys
  def create
    new_key = SshKeyForm.new(
      title: ssh_key_params[:title],
      key: ssh_key_params[:key],
      key_type: ssh_key_params[:key_type],
      current_user: current_user
    ).create_key

    # This flow is similar to PublicKeysController#create
    if new_key.new_record?
      flash[:error] = new_key.errors.full_messages.to_sentence
    else
      flash[:notice] = "You have successfully added the key '#{new_key.title}'."
    end


    redirect_to settings_keys_path
  end

  private

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def ssh_key_params
    params.require(:ssh_key).permit %i[title key key_type]
  end
end
