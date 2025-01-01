# typed: true
# frozen_string_literal: true

class AddUserAccountsBusinessOrchestration < BusinessOrchestration
  job_start

  step :fetch_user_emails do
    data[:user_emails_hash] = UserEmail.verified.where(user_id: user_ids).pluck(:email, :user_id).to_h
  end

  step :fetch_external_identities_emails do
    emails = data[:user_emails_hash]
    # Get email addresses from any linked external identities as well
    # Since we also match GHES users to GitHub accounts based on external identity supplied emails
    ExternalIdentity.where(
      user_id: user_ids,
      provider: T.must(business).all_external_identity_providers
    ).with_attributes.each do |ext_ident|
      ext_ident.emails.each do |email|
        # If we already have the email from verified emails, don't overwrite the user_id for it
        unless emails.has_key?(email)
          emails[email] = ext_ident.user_id
        end
      end
    end

    data[:user_emails_hash] = emails
  end

  step :update_existing_accounts do
    accounts_hash = T.must(business).enterprise_users_from_emails(data[:user_emails_hash].keys)

    # For any server-only BusinessUserAccount's that we found, associate them with the User
    # instead of creating a new BusinessUserAccount
    accounts_hash.each do |email, business_user_account|
      business_user_account.update(user_id: data[:user_emails_hash][email]) if business_user_account.present?
      T.must(user_ids).delete(data[:user_emails_hash][email])
    end
  end

  step :create_new_accounts do
    users = User.where(id: user_ids).map { |u| [u.id, u] }.to_h
    user_account_ids = T.must(user_ids).map do |user_id|
      next if users[user_id].nil?
      begin
        T.must(business).user_accounts.create(
          user: users[user_id],
          business_roles_bitfield: data[:business_roles_bitfield]
        ).id
      rescue ActiveRecord::RecordNotUnique => e
        # Ignore exception in a race condition when an account was created from another background job
        # while this is running.
        Failbot.report(e)
      end
    end.flatten.compact

    BusinessUserAccountUpdateAttributesJob.enqueue(T.must(business), user_account_ids: user_account_ids)
  end
end
