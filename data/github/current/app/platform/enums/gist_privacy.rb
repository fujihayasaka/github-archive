# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class GistPrivacy < Platform::Enums::Base
      description "The privacy of a Gist"

      value "PUBLIC", "Public", value: "public"
      value "SECRET", "Secret", value: "secret"
      value "ALL", "Gists that are public and secret", value: "all"
    end
  end
end
