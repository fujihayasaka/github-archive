# typed: true
# frozen_string_literal: true

module GitAuth
  class SSHKey
    # For now, return nil if no record is found,
    # to match the behavior of the existing Rails
    # associations.
    #
    # Note that this class uses ApplicationRecord::Domain in order to
    # avoid relying on ActiveRecord. This is the first step in decoupling
    # gitauth from the github/github, and the lowest level of raw SQL
    # that is currently acceptable in the github/github codebase.
    class Repository
      def self.find(id)
        return if id.nil?

        name, owner_id = ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, repository_id: id)).first
          SELECT name, owner_id
          FROM repositories
          WHERE id=:repository_id
        SQL
        return if name.nil?

        owner, display_owner = ApplicationRecord::Domain::Users.connection.select_rows(Arel.sql(<<-SQL, user_id: owner_id)).first
          SELECT login, display_login
          FROM users
          WHERE id=:user_id
        SQL
        new(id: id, owner: owner, display_owner: display_owner, name: name)
      end

      attr_reader :id, :owner, :display_owner, :name
      def initialize(id:, owner:, display_owner:, name:)
        @id    = id
        @owner = owner
        @display_owner = display_owner
        @name  = name
      end

      def name_with_owner
        "#{owner}/#{name}" # rubocop:disable GitHub/DoNotAllowLogin
      end
      alias_method :nwo, :name_with_owner

      def name_with_display_owner
        "#{display_owner}/#{name}"
      end
    end
  end
end
