# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ProfilesKv < Platform::Loader
      def self.load(key)
        self.for.load(key)
      end

      def fetch(keys)
        keys.zip(Profiles::Kv.store.mget(keys).value!).to_h
      end
    end
  end
end
