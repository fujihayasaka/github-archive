# typed: true
# frozen_string_literal: true
class StafftoolsRole < ApplicationRecord::Ballast
  include GitHub::Validations
  has_many :user_stafftools_roles, dependent: :destroy

  validates :name, presence: true, unicode3: true
  validates :name, uniqueness: { case_sensitive: false }, if: -> do
    T.bind(self, StafftoolsRole)
    errors[:name].blank?
  end

  def users
    # Users live in a different DB, so has_many through won't work
    @users ||= User.where(id: user_stafftools_roles.pluck(:user_id))
  end
end
