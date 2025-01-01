# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class DeploymentReviewer < Platform::Unions::Base
      description "Users and teams."

      possible_types(
        Objects::User,
        Objects::Team,
      )
    end
  end
end
