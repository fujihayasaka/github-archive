# typed: strict
# frozen_string_literal: true

module PersonalAccessTokensControllerHelper
  include GranularPermissionsHelper
  extend T::Sig

  # Currently filters are limited to strings of the following forms
  #
  # Examples
  #
  #   "owner:valid-user-login"
  #   "repository:valid-repository-name"
  #   "permission:organization_secrets_write"
  #   "owner:valid-user-login repository:valid-repository-name"
  #
  # The login part of this regexp was taken from User::LOGIN_REGEX_FOR_EMUS and User::LOGIN_REGEX
  # Rubular for EMU logic https://rubular.com/r/mR079p9MXcraMv
  OWNER_REGEX      = /\Aowner\:(?<login>([a-zA-Z0-9]+(-[a-zA-Z0-9]+)*(_[a-zA-Z0-9]+))|[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*)/
  REPOSITORY_REGEX = /(repository\:(?<name>(\w|-|_|)*))/
  PERMISSION_REGEX = /(permission\:(?<permission>(\w|_|)*))/

  sig do
    params(organization: Organization, attr: String, query: T.nilable(String))
    .returns(T.any(NilClass, User, Repository, T.nilable(T::Hash[String, Symbol])))
  end
  def fetch_from_filter(organization, attr, query)
    return unless query.present?

    case attr
    when "owner"
      return unless (result = query.match(OWNER_REGEX))
      User.find_by_login(result[:login])
    when "repository"
      return unless (result = query.match(REPOSITORY_REGEX))
      organization.repositories.find_by(name: result[:name])
    when "permission"
      return unless (result = query.match(PERMISSION_REGEX))
      parse_permission_string(result[:permission])
    end
  end
end
