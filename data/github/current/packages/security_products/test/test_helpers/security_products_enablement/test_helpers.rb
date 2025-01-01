# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement::TestHelpers
  extend T::Sig

  sig { void }
  def self.stub_autoql_disabled
    CodeScanning::AutoCodeql.any_instance.stubs(enabled?: false)
  end
end
