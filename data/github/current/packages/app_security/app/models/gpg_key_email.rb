# typed: true
# frozen_string_literal: true

class GpgKeyEmail < ApplicationRecord::Domain::Users
  belongs_to :gpg_key
  belongs_to :user_email

  # rubocop:todo Rails/InverseOf
  belongs_to :verified_user_email,
    -> { where(state: "verified") },
    class_name: "UserEmail",
    foreign_key: :user_email_id
  # rubocop:enable Rails/InverseOf
end
