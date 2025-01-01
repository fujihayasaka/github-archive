# typed: true
# frozen_string_literal: true

class Codespaces::ShowAuthComponent < ApplicationComponent

  attr_reader :codespace,
              :github_token,
              :github_token_valid_after,
              :user,
              :repository,
              :connection,
              :user_settings,
              :editor

  def initialize(codespace:, github_token:, github_token_valid_after:, user:, user_settings:, connection: nil, repository: nil, editor: nil)
    @codespace = codespace
    @github_token = github_token
    @github_token_valid_after = github_token_valid_after
    @user = user
    @connection = connection
    @repository = repository
    @user_settings = user_settings
    @editor = editor
  end

  def before_render
    SecureHeaders::append_content_security_policy_directives(
      request,
      form_action: form_actions,
      preserve_schemes: FeatureFlag.vexi.enabled?(:codespaces_developer, user, default: false),
    )
  end

  private

  def web_portal_url_formats
    if FeatureFlag.vexi.enabled?(:codespaces_developer, user, default: false)
      # This flag allows the user to possibly pick from any environment so
      # we allow all environments for CORS.
      Codespaces::Vscs.web_portal_url_formats
    else
      # Without this flag the codespace will ultimately be provisioned in
      # the default vscs target for the current environment. We don't try to
      # grab this from the codespace itself because the codespace is not
      # necessarily provisioned by the time we render this component.
      [Codespaces::Vscs.default_target_config[:web_portal_url_format]]
    end
  end

  def form_actions
    web_portal_url_formats.map do |host|
      "#{host % { name: codespace.name, second_level_domain: GitHub.codespaces_web_portal_second_level_domain }}"
    end.sort
  end
end
