# typed: strict
# frozen_string_literal: true

# The Mutable module is responsible for bringing together the business, organization, and user operations
# to provide a single concern for mutating policies. This can be used to make your policy mutable for all three types
# of entities with a single include.

module Copilot
  module Policies
    module Concerns
      module Mutable
        extend T::Helpers

        abstract!

        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable
        include Copilot::Policies::Concerns::User::Mutable
      end
    end
  end
end
