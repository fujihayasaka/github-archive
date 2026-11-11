# typed: true
# frozen_string_literal: true

class UserSeenFeature < ApplicationRecord::Collab
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  belongs_to :feature
end
