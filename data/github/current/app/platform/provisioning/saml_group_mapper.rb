# typed: true
# frozen_string_literal: true

# Mapper responsible for taking GroupData provided by the identity provider
# via SAML protocol and mapping that to an ExternalIdentity.
module Platform::Provisioning
  module SamlGroupMapper
    # Public: Builds an external identity for a IdP Group represented by an Enterprise organization
    #
    # target        - The Business which the identity will be under.
    # user          - (Optional) The Organization to which the identity will be linked.
    # user_data     - group data from the identity provider (not used here)
    #
    # Returns an ExternalIdentity
    def self.find_or_build_identity(target:, user: nil, user_data:)
      provider = target.external_identity_session_owner.saml_provider

      ExternalIdentity.new(provider: provider, user: user)
    end

    def self.set_user_data(identity:, user_data:)
      identity.saml_user_data = user_data

      # set the name id
      identity.name_id = user_data.name_id

      identity
    end
  end
end
