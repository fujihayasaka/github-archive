# typed: true
# frozen_string_literal: true

# GHEC Licenses a business user account can have in a business.
module BusinessUserAccount::GhecLicenses
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig
  requires_ancestor { BusinessUserAccount }

  # Public: Returns a symbol representing the ghec license the user has.
  sig { returns(T.nilable(Symbol)) }
  def ghec_license_type
    return if ghec_license.nil?

    T.must(ghec_license).to_sym
  end

  # Public: Checks if the user has a specified ghec license.
  sig { returns(T::Boolean) }
  def has_ghec_license?
    !ghec_license_type.nil? && ghec_license_type != :unlicensed
  end

  # Public: Checks if a new license is changing the user's license status, from unlicensed to licensed or vice versa.
  sig { params(new_license: Symbol).returns(T::Boolean) }
  def changing_licensed_status?(new_license)
    new_license == :unlicensed ? has_ghec_license? : !has_ghec_license?
  end
end
