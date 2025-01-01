# typed: true
# frozen_string_literal: true

class Api::UserEmails < Api::App
  include ReceiveSchemaWithOpenApi

  # List a User's email addresses
  get "/user/emails", operation_id: "users/list-emails-for-authenticated-user" do
    control_access :list_user_emails,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    emails = current_user.emails.order("id ASC")
    emails = paginate_rel(emails)

    GitHub::PrefillAssociations.prefill_associations(emails, :email_roles)

    deliver :user_email_hash, emails
  end

  # List the authenticated user's public email addresses
  get "/user/public_emails", operation_id: "users/list-public-emails-for-authenticated-user" do
    control_access :list_user_public_emails,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    user_emails = UserEmail.where(email_roles: current_user.email_roles.where(public: true))
      .where.not(email_roles: current_user.email_roles.where(public: false))
      .order(id: :desc)
      .paginate(pagination)

    GitHub::PrefillAssociations.prefill_associations(user_emails, :email_roles)

    deliver :user_email_hash, user_emails
  end

  # Create (add) email address(es) to a User
  # https://developer.github.com/v3/users/emails/#add-email-addresses
  post "/user/emails", operation_id: "users/add-email-for-authenticated-user" do
    control_access :add_user_emails,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if !current_user.change_email_enabled?
      if current_user.is_enterprise_managed?
        deliver_error! 403, message: "Email addresses must be added in the Identity Provider."
      else
        deliver_update_denied_using_ldap_sync! "Email addresses must be added in the #{GitHub.auth.name} Identity Provider."
      end
    end

    data = receive
    emails = data.is_a?(Hash) ? data["emails"] : Array(data)

    # This can be removed once we begin validation using a JSON schema
    message = "Emails must be an Array of String values."
    if emails.blank? || !emails.is_a?(Array)
      deliver_error! 422, message: message
    end
    if bogus = emails.detect { |email| !email.is_a?(String) }
      deliver_error! 422, message: message, errors: [api_error(:User, :email, :invalid, value: bogus)]
    end

    # Introducing strict validation of the user-email.add-emails
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # TODO: replace `receive` with `receive_with_schema`
    # see: https://github.com/github/ecosystem-api/issues/1555
    _ = receive_with_schema("user-email", "add-emails", skip_validation: true)

    emails.each do |email|
      saved = current_user.add_email(email)
      deliver_error! 422 if saved.blank?

      if saved.errors.present? && saved.errors.where(:email, :sanctioned_email).any?
        deliver_error! 422, message: ::TradeControls::Notices.notice_as_plaintext(:sanctioned_domain_email_warning), documentation_url: GitHub.trade_controls_help_url
      elsif saved.errors.present? && saved.errors.where(:email, :disposable_email).any?
        deliver_error! 422, message: "Email #{UserEmail::GENERIC_DOMAIN_ERROR}"
      elsif saved.errors.present?
        deliver_error! 422
      end
    end

    GitHub::PrefillAssociations.prefill_associations(current_user.emails, :email_roles)

    deliver :user_email_hash, current_user.emails, status: 201
  end

  # Delete (remove) email address(es) from a User
  delete "/user/emails", operation_id: "users/delete-email-for-authenticated-user" do
    control_access :delete_user_emails,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if !current_user.change_email_enabled?
      if current_user.is_enterprise_managed?
        deliver_error! 403, message: "Email addresses must be removed in the Identity Provider."
      else
        deliver_update_denied_using_ldap_sync! "Email addresses must be removed in the #{GitHub.auth.name} Identity Provider."
      end
    end

    data = receive
    emails = data.is_a?(Hash) ? data["emails"] : Array(data)

    # This can be removed once we begin validation using a JSON schema
    message = "Emails must be an Array of String values."
    if emails.blank?
      deliver_error! 422, message: message
    end
    if bogus = emails.detect { |email| !email.is_a?(String) }
      deliver_error! 422, message: message, errors: [api_error(:User, :email, :invalid, value: bogus)]
    end
    # Introducing strict validation of the user-email.delete-emails
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # TODO: replace `receive` with `receive_with_schema`
    # see: https://github.com/github/ecosystem-api/issues/1555
    _ = receive_with_schema("user-email", "delete-emails", skip_validation: true)

    emails.each do |email|
      if current_user.emails.size == 1
        deliver_error! 422,
          message: "Cannot delete last email address",
          errors: [api_error(:User, :email, :invalid, value: email)]
      end

      unless current_user.remove_email(email)
        deliver_error! 404
      end
    end

    deliver_empty(status: 204)
  end

  # Toggle email visibility
  patch "/user/email/visibility", operation_id: "users/set-primary-email-visibility-for-authenticated-user" do
    unless GitHub.stealth_email_enabled?
      message = "Email visibility cannot be toggled in this environment."
      deliver_error! 422, message: message
    end

    control_access :toggle_email_visibility,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if current_user&.is_emu_and_not_first_owner?
      deliver_error! 403, message: "Changing visibility of an email is forbidden for users managed by an Identity Provider."
    end

    data = receive_with_schema("user-email", "update-visibility")

    email = current_user.primary_user_email

    if email.visibility == data["visibility"]
      message = "Email visibility is unchanged."
      deliver_error!(422, message: message)
    end

    if email.toggle_visibility
      deliver :user_email_hash, [email]
    else
      deliver_error!(422)
    end
  end
end
