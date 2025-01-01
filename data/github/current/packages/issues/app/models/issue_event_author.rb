# typed: true
# frozen_string_literal: true

class IssueEventAuthor < ApplicationRecord::Domain::IssuesPullRequests
  include Spam::Spammable

  extend T::Sig
  belongs_to :issue_event
  belongs_to :author, class_name: "User"

  before_validation :set_repository_id, on: :create

  validates :repository_id, presence: true, on: :create

  setup_spammable(:author)

  private

  sig { void }
  def set_repository_id
    self.repository_id = T.must(issue_event&.repository_id)
  end
end
