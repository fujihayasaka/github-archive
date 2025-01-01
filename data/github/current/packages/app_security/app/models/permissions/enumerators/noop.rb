# typed: true
# frozen_string_literal: true

module Permissions
  module Enumerators
    class Noop < Permissions::Enumerator
      def actor_ids
        []
      end
    end
  end
end
