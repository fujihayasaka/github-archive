# typed: true
# frozen_string_literal: true

module GitHub
  class UnexpectedDatastoreAccess < StandardError
    def failbot_context
      { app: "github-multi-dc" }
    end
  end
end
