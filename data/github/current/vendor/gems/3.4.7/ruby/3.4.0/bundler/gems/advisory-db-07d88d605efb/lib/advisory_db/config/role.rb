# frozen_string_literal: true

module AdvisoryDB
  module Config
    module Role
      def role
        ENV.fetch("ADVISORY_DB_ROLE", nil)
      end
    end

    include Role
  end
end
