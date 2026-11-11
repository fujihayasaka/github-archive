# typed: strict
# frozen_string_literal: true

module Api::App::LdapDependency
  extend T::Helpers
  requires_ancestor { Api::App::ErrorDependency }

  sig { params(message: String).void }
  def deliver_update_denied_using_ldap_sync!(message)
    url = "#{GitHub.enterprise_admin_help_url}/articles/ldap-sync"

    deliver_error! 403, message: message, documentation_url: url
  end
end
