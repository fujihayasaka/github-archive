# typed: true
# frozen_string_literal: true

class Api::UserSocialAccounts < Api::App
  include ReceiveSchemaWithOpenApi

  # List the current User's social accounts
  get "/user/social_accounts", operation_id: "users/list-social-accounts-for-authenticated-user" do
    control_access :read_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    social_accounts = Array(current_user.profile_social_accounts)
    social_accounts = paginate_rel(social_accounts)

    deliver :social_account_hash, social_accounts
  end

  # List a User's social accounts
  get "/user/:user_id/social_accounts", operation_id: "users/list-social-accounts-for-user" do
    user = find_user!
    control_access :read_user_public,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    social_accounts = Array(user.profile_social_accounts)
    social_accounts = paginate_rel(social_accounts)

    deliver :social_account_hash, social_accounts
  end

  # Add a new social account to the current User's profile
  post "/user/social_accounts", operation_id: "users/add-social-account-for-authenticated-user" do
    control_access :update_user_profile,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    recognition_results = data["account_urls"].map do |url|
      SocialAccount.create(key: "generic", url:).recognize(defer_expensive: true)
    end

    existing_accounts = Array(current_user.profile_social_accounts)
    incoming_accounts = recognition_results.map(&:account)

    current_user.profile_social_accounts = existing_accounts + incoming_accounts
    if current_user.save
      if recognition_results.any?(&:deferred)
        RecognizeSocialAccountJob.perform_later(current_user.profile.id)
      end

      deliver :social_account_hash, incoming_accounts, status: 201
    else
      deliver_error!(422,
        errors: current_user.errors,
        documentation_url: "/rest/users/social-accounts#add-social-account-for-authenticated-user")
    end
  end

  # Delete social accounts from the current User's profile
  delete "/user/social_accounts", operation_id: "users/delete-social-account-for-authenticated-user" do
    control_access :update_user_profile,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    account_urls = data["account_urls"].to_set
    kept_accounts = Array(current_user.profile_social_accounts).reject do |account|
      account_urls.delete?(account.url)
    end

    if account_urls.any?
      errors = account_urls.map do |url|
        api_error(:User, :profile_social_accounts, :invalid, value: url)
      end

      deliver_error!(422,
        message: "Account not found",
        errors: errors,
        documentation_url: "/rest/users/social-accounts#delete-social-account-for-authenticated-user")
    else
      current_user.profile_social_accounts = kept_accounts
      if current_user.save
        deliver_empty(status: 204)
      else
        deliver_error!(422,
          errors: current_user.errors,
          documentation_url: "/rest/users/social-accounts#delete-social-account-for-authenticated-user")
      end
    end
  end
end
