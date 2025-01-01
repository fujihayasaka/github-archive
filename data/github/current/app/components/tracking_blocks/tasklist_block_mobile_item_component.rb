# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class TasklistBlockMobileItemComponent < TasklistBlockItemComponent
    include GitHub::Memoizer

    UUID = T.type_alias { String }

    def initialize(**kwargs)
      T.bind(self, T.untyped)
      super
    end

    # Public: returns the uuid of the item if exists, otherwise it returns a
    # memoized (and therefore stable) uuid. In practice this is heplful for
    # creating a unique id for the input element, easing accessibility concerns.
    sig { returns(UUID) }
    memoize def input_uuid
      uuid.presence || SecureRandom.uuid
    end
  end
end
