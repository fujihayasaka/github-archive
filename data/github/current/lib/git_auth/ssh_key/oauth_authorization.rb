# typed: true
# frozen_string_literal: true

module GitAuth
  class SSHKey
    # Note that this class uses ApplicationRecord::Domain in order to
    # avoid relying on ActiveRecord. This is the first step in decoupling
    # gitauth from the github/github, and the lowest level of raw SQL
    # that is currently acceptable in the github/github codebase.
    class OauthAuthorization
      def self.find(id)
        # Return a null object if there's no ID.
        return new(id: id, application_id: nil, application_type: nil) if id.nil?

        app_id, app_type = ApplicationRecord::Domain::Users.connection.select_rows(Arel.sql(<<-SQL, oauth_authorization_id: id)).first
        SELECT application_id, application_type
        FROM oauth_authorizations
        WHERE id = :oauth_authorization_id
        SQL
        new(id: id, application_id: app_id, application_type: app_type)
      end

      attr_reader :id, :application_id, :application_type
      def initialize(id:, application_id:, application_type:)
        @id               = id
        @application_id   = application_id
        @application_type = application_type
      end
    end
  end
end
