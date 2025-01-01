# typed: true
# frozen_string_literal: true

class Integrations::FormView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer

  attr_reader :integration

  SAME_AS_CALLBACK_URL_HINT = "Users will be redirected to the 'User authorization callback URL' to complete additional setup."
  SETUP_URL_HINT = "Users will be redirected to this URL after installing your GitHub App to complete additional setup."
  UNAVAILABLE_WHEN_REQUESTING_ON_INSTALL = "Unavailable when requesting OAuth during installation."

  delegate :owner, :default_permissions, :default_events, to: :integration

  def hook
    @hook ||= if (hook = integration.hook)
      hook
    elsif integration.new_record?
      integration.build_hook(active: true)
    else
      integration.build_hook
    end
  end

  def application_callback_urls
    return @application_callback_urls if defined?(@application_callback_urls)

    # Build a single record so that we can show the text
    # field if there aren't any set.
    if integration.application_callback_urls.none?
      integration.application_callback_urls.build
    end

    @application_callback_urls = integration.application_callback_urls
  end

  def page_title
    if integration.persisted?
      "Edit integration - #{ integration.name_was }"
    else
      "Register new GitHub App"
    end
  end

  def selected_link
    :integrations
  end

  def hook_url_error
    errors = integration.hook.errors[:url]
    return unless errors.any?
    "Webhook URL #{errors.to_sentence}"
  end

  def human_event_name(item)
    item.humanize
  end

  def show_permission_fields?
    integration.new_record?
  end

  def show_privacy_fields?
    integration.new_record?
  end

  def show_public_visibility?
    !integration.owner.is_a?(Business)
  end

  def show_event_fields?
    integration.new_record?
  end

  def submit_text
    if integration.new_record?
      "Create GitHub App"
    else
      "Save changes"
    end
  end

  def setup_url_hint
    if integration.can_request_oauth_on_install?
      SAME_AS_CALLBACK_URL_HINT
    else
      SETUP_URL_HINT
    end
  end

  def redirect_on_update_hint
    if integration.can_request_oauth_on_install?
      redirect_on_update_request_oauth_on_install_hint
    else
      redirect_on_update_request_setup_url_hint
    end
  end

  def redirect_on_update_request_oauth_on_install_hint
    "Redirect users to the 'User authorization callback URL' after installations are updated (E.g repositories added/removed)."
  end

  def redirect_on_update_request_setup_url_hint
    "Redirect users to the 'Setup URL' after installations are updated (E.g. repositories added/removed)."
  end

  def private_checked?
    integration.persisted? ? integration.private? : integration_can_be_private?
  end

  def public_label
    owner_is_enterprise_managed? ? "This enterprise" : "Any account"
  end

  def public_caption
    if owner_is_enterprise_managed?
      "Allow this GitHub App to be installed by any organization in your enterprise."
    else
      "Allow this GitHub App to be installed by any user or organization."
    end
  end

  memoize def integration_can_be_private?
    integration.can_make_private?
  end

  memoize def owner_is_enterprise_managed?
    owner = integration&.owner

    case integration&.owner
    when Organization
      owner.enterprise_managed_user_enabled?
    when User
      owner.is_enterprise_managed?
    else
      false
    end
  end
end
