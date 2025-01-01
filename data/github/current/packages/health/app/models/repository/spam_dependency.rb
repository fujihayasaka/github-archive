# typed: false
# frozen_string_literal: true

module Repository::SpamDependency
  # Check the repository for spam
  #
  # options - currently unused
  def check_for_spam(options = {})
    return if spammy?
    reason = GitHub::SpamChecker.test_repo(self)
    owner.safer_mark_as_spammy(reason: reason) if reason
  end
end
