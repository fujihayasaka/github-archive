# typed: strict
# frozen_string_literal: true

module OctoCore::SecurityUtils
  extend T::Sig

  # Constant time string comparison.
  sig { params(a: String, b: String).returns(T::Boolean) }
  def self.secure_compare(a, b)
    Rack::Utils.secure_compare(a, b)
  end
end
