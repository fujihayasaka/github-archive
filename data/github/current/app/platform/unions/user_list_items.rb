# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class UserListItems < Platform::Unions::Base
      description "Types that can be added to a user list."

      possible_types(Objects::Repository)
    end
  end
end
