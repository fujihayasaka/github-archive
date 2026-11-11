# typed: strict
# frozen_string_literal: true

module Licensing::DismissalHelper
  private

  sig { params(key: String, expires: T.nilable(Time)).void }
  def dismiss(key, expires: nil)
    Billing::Kv.store.set(key, Time.now.utc.iso8601, expires: expires)
  end

  sig { params(key: String).returns(T::Boolean) }
  def is_dismissed?(key)
    Billing::Kv.store.exists(key).value!
  end
end
