# typed: true
# frozen_string_literal: true

class Stafftools::SocialAccountsController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_social_account_exists

  def update
    if this_user.profile.update(encoded_social_accounts: new_encoded_social_accounts)
      flash[:notice] = "Social account updated successfully."
    else
      flash[:error] =
        "Unable to update social account. #{this_user.profile.errors.full_messages.to_sentence}."
    end

    redirect_to stafftools_user_profile_path(this_user)
  end

  private

  def ensure_social_account_exists
    render_404 unless existing_social_account
  end

  memoize def existing_social_account
    encoded_social_accounts.find do |account|
      account["key"] == params[:existing_provider_key] && account["url"] == params[:provider_url]
    end
  end

  memoize def encoded_social_accounts
    this_user.profile&.encoded_social_accounts || []
  end

  def new_encoded_social_accounts
    encoded_social_accounts.dup.tap do |new_accounts|
      new_accounts[new_accounts.index(existing_social_account)] = {
        "key" => params[:new_provider_key],
        "url" => params[:provider_url],
      }
    end
  end
end
