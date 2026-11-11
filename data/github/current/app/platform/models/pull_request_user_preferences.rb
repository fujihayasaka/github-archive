# typed: true
# frozen_string_literal: true

class Platform::Models::PullRequestUserPreferences
  attr_reader :user, :pull_request

  # user - a User object
  # pull_request - a PullRequest object
  def initialize(user:, pull_request: nil)
    @user = user
    @pull_request = pull_request
  end

  def ignore_whitespace
    pull_request&.ignore_whitespace?(user)
  end

  def diff_view
    user.split_diff_preferred ? "split" : "unified"
  end

  def tab_size
    ::Platform::Loaders::ActiveRecordAssociation.load(user, :user_settings_record).then do
      user.settings.get(:tab_size)
    end
  end
end
