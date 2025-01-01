# typed: true
# frozen_string_literal: true

class UserReviewedFile < ApplicationRecord::Collab

  include GitHub::Relay::GlobalIdentification

  belongs_to :pull_request
  belongs_to :user
  has_one :repository, through: :pull_request, disable_joins: true

  attribute :filepath, UnconvertedStringFromBinary.new

  validates :filepath, presence: true
  validates :head_sha, presence: true
  validates :pull_request, presence: true
  validates :user, presence: true
  validates_uniqueness_of :filepath, scope: [:pull_request, :user], case_sensitive: true
  validate :filepath_part_of_pr

  scope :dismissed, -> { where(dismissed: true) }
  scope :not_dismissed, -> { where(dismissed: false) }

  def self.for(pull_request)
    where(pull_request_id: pull_request.id)
  end

  def filepath_part_of_pr
    pr_paths = T.must(pull_request).changed_paths_for_codeowners.map do |path|
      path.dup.force_encoding(Encoding::UTF_8)
    end

    unless pr_paths.include?(filepath)
      errors.add(:filepath, "must be part of pull request")
    end
  end

  # A safe-to-use form of the binary stored path
  def path
    @path ||= filepath.dup.force_encoding(Encoding::UTF_8)
  end
end
