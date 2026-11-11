# typed: true
# frozen_string_literal: true

module Mobile
  class Loader < Platform::Loader
    def self.load(key)
      self.for.load(key)
    end

    def fetch(keys)
      keys.zip(Mobile::KV.store.mget(keys).value!).to_h
    end
  end
end
