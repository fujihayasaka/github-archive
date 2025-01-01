# typed: true
# frozen_string_literal: true

module ApplicationRecord
  # This connection class is only used for managing the schema of the `vt` database
  # during development.
  #
  # It can not be used to connect to the `vt` database in production.
  #
  # This inherits from `mysql1` to avoid opening a connection to `vt_primary`,
  # as this connection is not configured in production.
  class VT < Mysql1
    self.abstract_class = true

    if !Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      connects_to_same database: :vt_primary
    end
  end
end
