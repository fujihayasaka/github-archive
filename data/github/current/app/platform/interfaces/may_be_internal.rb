# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module MayBeInternal
      include Platform::Interfaces::Base

      description "Entities that may be internal (secret)."
      visibility :internal

      field :is_internal, Boolean,
        visibility: :internal,
        description: "Check if this comment is internal.",
        null: false

      def is_internal
        false
      end
    end
  end
end
