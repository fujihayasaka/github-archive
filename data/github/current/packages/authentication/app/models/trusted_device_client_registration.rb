# typed: true
# frozen_string_literal: true

class TrustedDeviceClientRegistration < ApplicationRecord::Domain::Users
  belongs_to :user
  belongs_to :authenticated_device
  # rubocop:todo Rails/InverseOf
  belongs_to :trusted_device,
    -> { T.unsafe(self).passkeys },
    foreign_key: :u2f_registration_id,
    class_name: "U2fRegistration"
  # rubocop:enable Rails/InverseOf

  validate :validate_trusted_device, :validate_same_owner
  validates :authenticated_device, presence: true

  def validate_same_owner
    if user.nil?
      errors.add(:base, "user was not supplied")
    elsif [trusted_device, authenticated_device].any? { |device| device && device.user != user }
      errors.add(:base, "devices not owned by same user")
    end
  end

  def validate_trusted_device
    if trusted_device
      unless trusted_device&.is_passkey_registration?
        errors.add(:base, "security key provided instead of passkey")
      end
    else
      # ugly heuristic: `self.trusted_device` can return nil when a
      # security key is provided. Therefore, we can't check
      # `self.trusted_device.is_passkey_registration?`. Also, `u2f_registration`
      # is not defined here (because of our `belongs_to` configuration).
      # However, the raw database value used as a foreign key is available.
      if self.u2f_registration_id.nil?
        errors.add(:base, "passkey not supplied")
      else
        errors.add(:base, "security key provided instead of passkey")
      end
    end
  end

  def readonly?
    !new_record?
  end
end
