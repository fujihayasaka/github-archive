# typed: true
# frozen_string_literal: true

module LabelEducationHelper
  extend T::Helpers
  extend T::Sig

  abstract!

  sig { abstract.returns(T.untyped) }
  def logged_in?; end

  sig { abstract.returns(T.untyped) }
  def current_user; end

  sig { abstract.returns(T.untyped) }
  def current_repository; end

  sig { abstract.returns(T.untyped) }
  def current_user_can_push?; end

  # Public: Returns true if the viewer should see a banner explaining how GitHub uses first-time contributor labels
  #
  # Returns a Boolean.
  def show_maintainer_label_education_banner?
    !GitHub.enterprise? &&
      current_repository &&
      logged_in? &&
      !current_repository.private? &&
      current_repository.has_issues? &&
      !current_repository.fork? &&
      !current_repository.spammy? &&
      !current_user.dismissed_notice?("maintainer_label_education_banner") &&
      current_repository.writable? &&
      current_user_can_push? &&
      !current_user.blocked_by?(current_repository.owner)
  end

  def help_wanted_label
    current_repository.help_wanted_label || Label.default_for(Labelable::HELP_WANTED_NAME)
  end

  def good_first_issue_label
    current_repository.good_first_issue_label || Label.default_for(Labelable::GOOD_FIRST_ISSUE_NAME)
  end
end
