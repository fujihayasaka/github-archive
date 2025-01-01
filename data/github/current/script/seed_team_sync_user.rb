# typed: true
# frozen_string_literal: true

require_relative "seeds/factory_bot_loader"

email = "team-sync@ghemu.onmicrosoft.com"
username = "team-sync-user"
if !User.where(login: username).first.nil?
  puts "team-sync-user already exists"
else
  user = FactoryBot::create(:user, :verified, email: email, login: username)
  team_sync_org = T.must(Organization.where(login: "team-sync").first)
  saml_user_data = Platform::Provisioning::SamlUserData.new([
  {
      "name": "http://schemas.microsoft.com/identity/claims/displayname",
      "value": "Team Sync",
      "metadata": {}
    },
    {
      "name": "http://schemas.microsoft.com/identity/claims/objectidentifier",
      "value": "d5d26d89-d139-437c-9532-355793a947a0",
      "metadata": {}
    },
    {
      "name": "http://schemas.microsoft.com/identity/claims/tenantid",
      "value": "8039e47d-8f9e-4f74-b0e8-9201aa7a4895",
      "metadata": {}
    },
    {
      "name": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
      "value": "team-sync@ghemu.onmicrosoft.com",
      "metadata": {}
    },
    {
      "name": "NameID",
      "value": email,
      "metadata": { "Format": "urn:oasis:names:tc:SAML:1.1:nameid-format:persistent" }
    }
  ])
  provider = team_sync_org.saml_provider
  FactoryBot::create(:external_identity, provider: provider, user: user, saml_user_data: saml_user_data)
  team_sync_org.add_member user
end
