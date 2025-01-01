# typed: true
# frozen_string_literal: true

module Bot::RemoteAuthenticationDependency
  extend T::Helpers

  requires_ancestor { Bot }

  # Public: Generate a SignedAuthToken string.
  #
  # NOTE: The Why
  #
  # We'll need to do an IntegrationInstallation lookup to fill in what IntegrationInstallation
  # the Bot is trying to use for its permissions.
  #
  # On the off chance the Bot is not part connected to the IntegrationInstallation
  # we'll return the Bot as is.
  #
  # Returns a String.
  def signed_auth_token(options = {})
    if installation.present?
      options[:data] ||= Hash.new
      options[:data][:installation_id]   = installation.id
      options[:data][:installation_type] = installation.class.to_s
    end

    super(options)
  end
end
