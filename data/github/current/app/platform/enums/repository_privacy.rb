# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryPrivacy < Platform::Enums::Base
      description "The privacy of a repository"

      value "PUBLIC", "Public", value: "public"
      value "PRIVATE", "Private", value: "private"
    end
  end
end
