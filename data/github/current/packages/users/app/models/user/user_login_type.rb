# typed: true
# frozen_string_literal: true

# This custom login type is used to allow us to query by `login` with
# or without the EMU shortcode for the current tenant.
#
# The `serialize` method enables calls like `User.find_by(login: 'monalisa')`
# to generate a SQL query with `WHERE login='monalisa_avo'` where `avo` is the
# EMU shortcode for the current tenant.
class User::UserLoginType < ActiveRecord::Type::String
  def serialize(value)
    login = super(value)

    return login unless login.present?
    return login unless User.scope_to_current_tenant?
    return login if User.unique_tenant_login?(login)

    User.standardize_login(login, suffix: GitHub::CurrentTenant.get.shortcode)
  end
end
