# typed: true
# frozen_string_literal: true

class ReleaseMention < ApplicationRecord::Domain::Repositories
  belongs_to :release
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
end
