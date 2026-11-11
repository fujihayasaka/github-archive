# typed: true
# frozen_string_literal: true

class PullRequestUserReviews
  attr_reader :reviewed_paths, :dismissed_paths

  def initialize(pull_request, user)
    @pull_request, @user = pull_request, user

    dismissed_files = []
    reviewed_files = []

    if user.present?
      dismissed_files, reviewed_files = @user.reviewed_files.
        where(pull_request_id: @pull_request&.id).
        select(:dismissed, :filepath).
        partition(&:dismissed?)
    end

    @reviewed_paths = reviewed_files.map(&:path).to_set
    @dismissed_paths = dismissed_files.map(&:path).to_set
  end

  def reviewed?(path)
    return false if @user.nil?
    reviewed_paths.include?(path)
  end

  def dismissed?(path)
    return false if @user.nil?
    dismissed_paths.include?(path)
  end
end
