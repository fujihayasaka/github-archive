# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationInvitationType < Platform::Enums::Base
      description "The possible organization invitation types."

      value "USER", "The invitation was to an existing user.", value: :user
      value "EMAIL", "The invitation was to an email address.", value: :email
    end
  end
end
