# frozen_string_literal: true

class FixCommitPayload
  include ActiveModel::Validations

  attr_reader :commit_url

  def initialize(commit_url)
    @commit_url = commit_url
  end
end
