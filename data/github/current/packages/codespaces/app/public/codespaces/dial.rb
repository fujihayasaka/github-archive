# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Dial
    extend T::Helpers
    include ActiveModel::Validations

    abstract!

    attr_accessor :value

    def initialize(force_cache_miss: false)
      @value = GitHub.cache.fetch("dials:#{key}", { force: force_cache_miss }) do
        string_value = Codespaces::Kv.store.get(key).value { nil } || default_value.to_s
        transform_value_to_use(string_value)
      end
    end

    def self.update(value, update_cache: true)
      dial = new
      dial.value = value
      dial.save(update_cache:)
    end

    sig { abstract.returns(String) }
    def key; end

    sig { abstract.returns(T.untyped) }
    def default_value; end

    sig { abstract.returns(String) }
    def description; end

    def save(update_cache: false)
      if self.valid?
        Codespaces::Kv.store.set(key, value.to_s)
        if update_cache
          self.class.new(force_cache_miss: true)
        end
        true
      else
        false
      end
    end

    def transform_value_to_use(value)
      # child classes can overwrite this if they don't want to interact with value as a string
      value
    end
  end
end
