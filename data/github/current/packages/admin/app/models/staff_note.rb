# typed: true
# frozen_string_literal: true

class StaffNote < ApplicationRecord::Domain::Users
  include GitHub::UserContent

  belongs_to :user
  belongs_to :notable, polymorphic: true

  validates_presence_of :user, :notable, :note
  validates :body, unicode3: true

  scope :users, -> { where(notable_type: User.name) }
  scope :pinned, -> { where(is_pinned: true) }
  scope :unpinned, -> { where(is_pinned: false) }

  alias_attribute :body, :note

  def to_s
    note
  end

  def creator_name
    (user || ::User.ghost).name
  end
end
