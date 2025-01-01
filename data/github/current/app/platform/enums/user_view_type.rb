# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class UserViewType < Platform::Enums::Base
      description "Whether a user being viewed contains public or private information."

      value "PUBLIC", "A user that is publicly visible.", value: "public"
      value "PRIVATE", "A user containing information only visible to the authenticated user.", value: "private"

    end
  end
end
