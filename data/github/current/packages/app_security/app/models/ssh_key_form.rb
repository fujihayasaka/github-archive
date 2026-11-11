# typed: true
# frozen_string_literal: true

# Intended to be used from the Settings::Keys::SshKeysController only
class SshKeyForm
  include ActiveModel::Model
  attr_accessor :title, :key, :key_type, :current_user

  AUTHENTICATION_KEY_TYPE = "authentication"
  SIGNING_KEY_TYPE = "signing"

  # we only validate key_type here. We'll get more informative errors
  # back to the user by deferring to the models we try to create in `to_key`
  validates :key_type, presence: true, inclusion: { in: [AUTHENTICATION_KEY_TYPE, SIGNING_KEY_TYPE] }

  # Used in duck typing, returns true if the form's key_type is invalid
  def new_record?
    !valid?
  end

  # creates either a PublicKey or a GitSigningSshPublicKey
  def create_key
    return self unless valid?
    if key_type == AUTHENTICATION_KEY_TYPE
      create_public_key
    else
      create_signing_key
    end
  end

  private

  def create_public_key
    current_user.public_keys.create_with_verification(
      key: key,
      title: title,
      read_only: false,
      verifier: current_user
    )
  end

  def create_signing_key
    current_user.git_signing_ssh_public_keys.create(
      key: key,
      title: title
    )
  end
end
