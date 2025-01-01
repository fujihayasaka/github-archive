# typed: strict
# frozen_string_literal: true

module Repositories
  class CreateKeyLinkAttributes < T::Struct
    extend T::Sig

    prop :key_prefix, String
    prop :url_template, String
    prop :is_alphanumeric, T::Boolean, default: true

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      serialize.transform_keys(&:to_sym)
    end
  end
end
