# frozen_string_literal: true

module ::GitHub
  ##
  # Please keep this list in alphabetical order.
  # Once you have successfully created a user or org with a reserved login, please remove it from this list.
  #
  #
  # Allowed for both .com and Enterprise
  global_allowlist = %w(
  )

  AllowedLogins = Set.new(global_allowlist)
end
