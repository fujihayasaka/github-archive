# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Gitbackups < Mysql1
    # This inherits from `mysql1` to avoid opening a connection to `gitbackups_primary`.
    # We are not reading from or writing to that database cluster from `github/github`.
    # `gitbackups` is only here for managing the database schema via migrations. In the
    # future, this could potentially be replaced by skeefree and removed from `github/github`.
    #
    # `gitbackups` in `github/github` includes:
    #
    #   * This file
    #   * `gitbackups_primary` in `config/*/database.yml`
    #   * `db/gitbackups-structure.sql` and `db/initial_structure/gitbackups-structure.sql`
    #
    # Ref: https://github.com/github/github/issues/131342
    self.abstract_class = true

    unless Rails.env.production?
      connects_to_same database: :gitbackups_primary
    end
  end
end
