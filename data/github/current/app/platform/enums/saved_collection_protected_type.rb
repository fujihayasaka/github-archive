# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SavedCollectionProtectedType < Platform::Enums::Base
      description "Designates if a collection is a special, system-created collection."
      visibility :internal

      Dashboard::SavedCollection.protected_types.keys.each do |key|
        key = T.cast(key, String) # rubocop:todo GitHub/AvoidCast
        value key.upcase, "#{key.humanize} saved collection protected type", value: key
      end
    end
  end
end
