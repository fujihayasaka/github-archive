# typed: true
# frozen_string_literal: true

module GitAuth
  # For now, return nil if no record is found,
  # to match the behavior of the existing Rails
  # associations.
  #
  # Note that this class uses ApplicationRecord::Domain in order to
  # avoid relying on ActiveRecord. This is the first step in decoupling
  # gitauth from the github/github, and the lowest level of raw SQL
  # that is currently acceptable in the github/github codebase.
  class Login
    def self.find(id)
      return if id.nil?

      query = Arel.sql(<<-SQL, user_id: id)
        SELECT login, display_login
        FROM users
        WHERE id=:user_id
      SQL

      if GitHub.multi_tenant_enterprise?
        tenant_id = GitHub::CurrentTenant.get.try(:id) || User::MultiTenantEnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID
        query += Arel.sql(<<-SQL, business_id: tenant_id)
          AND business_id=:business_id
        SQL
      end

      login, display_login = ApplicationRecord::Domain::Users.connection.select_rows(query).first
      new(id: id, login: login, display_login: display_login) if login
    end

    attr_reader :id, :login, :display_login
    def initialize(id:, login:, display_login:)
      @id = id
      @login = login
      @display_login = display_login
    end
  end
end
