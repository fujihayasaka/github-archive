# typed: true
# frozen_string_literal: true

module Asset::Types
  extend T::Helpers

  interface!

  extend ActiveSupport::Concern

  sig { params(name: Symbol, values: T::Hash[T.untyped, T.untyped]).void }
  def self.enum(name, values); end

  included do
    enum :asset_type, { lfs: 0, registry: 1 }
  end
end
