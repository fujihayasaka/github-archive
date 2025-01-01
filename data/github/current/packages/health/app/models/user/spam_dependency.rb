# typed: false
# frozen_string_literal: true

module User::SpamDependency
  extend ActiveSupport::Concern

  SPAM_EXEMPTION_KEY = "SkipSpamChecks:User"
  SPAM_EXEMPTION_TTL = 5.minutes

  DELETION_DELAY_TABLES = [
    :issues,
    :issue_comments,
    :discussions,
    :discussion_comments,
  ]
  DELETION_DELAY = 5.minutes

  included do
    scope :spammy, -> { where(spammy: true) }
    scope :not_spammy, -> { where(spammy: false) }
    scope :filter_spam_for, lambda { |viewer|
      return if !GitHub.spamminess_check_enabled?
      return if viewer && viewer.site_admin?

      if viewer
        where("(users.spammy = false) OR users.id = ?", viewer.id)
      else
        where("users.spammy = false")
      end
    }
  end

  # Is this user exempt from spam checks for the first N minutes after account creation?
  # This is only used for staff members testing the signup flow.
  # See SignupController#user_exempt_from_spam_checks? for the conditions.
  def exempt_from_spam_check_after_signup?
    GitHub.employee_unicorn? &&
      created_at > SPAM_EXEMPTION_TTL.ago &&
      Spam::Kv.store.get("#{SPAM_EXEMPTION_KEY}:#{login}").value!
  end

  # Store this user's login in the KV to temporarily exempt them from further spam checks
  # (we are using `login` instead of `id` on purpose here, since we want to set this before the user record is created and has an ID)
  def mark_as_temporarily_exempt_from_spam_checks
    GitHub.dogstats.increment "spam.exempt_from_spam_check"
    Spam::Kv.store.set("#{SPAM_EXEMPTION_KEY}:#{login}", "1", expires: SPAM_EXEMPTION_TTL.from_now)
  end

  # Check this user for spamminess using `GitHub::SpamChecker`, and mark it as
  # spammy if found guilty.
  #
  # Returns nothing.
  def check_for_spam(options = {})
    return if self.spammy

    if reason = GitHub::SpamChecker.test_user(self)
      safer_mark_as_spammy(reason: reason)
    end
  end

  # Add this User's login to the (temporary) tainted login list if the User is
  # spammy, so the spammer can't immediately re-create an account with the same
  # name to keep his links working.
  #
  # Returns nothing.
  def mark_login_as_used
    # We're going to pass in the id of the existing User as the value, mostly
    # to see if it proves useful, since we have to give it *some* value.
    Spam.mark_login_tainted(login, id) if spammy?
  end

  # Defaults to false until toggled in stafftools
  def spammy_renaming_overridden?
    Stafftools::SpammyRenameDeleteOverride.overridden?(user: self, toggle_type: :renaming)
  end

  # Defaults to false until toggled in stafftools
  def spammy_deleting_overridden?
    Stafftools::SpammyRenameDeleteOverride.overridden?(user: self, toggle_type: :deleting)
  end

  # Defaults to false until toggled in stafftools
  def spammy_orgs_renaming_overridden?
    Stafftools::SpammyRenameDeleteOverride.orgs_overridden?(user: self, toggle_type: :renaming)
  end

  # Defaults to false until toggled in stafftools
  def spammy_orgs_deleting_overridden?
    Stafftools::SpammyRenameDeleteOverride.orgs_overridden?(user: self, toggle_type: :deleting)
  end

  # Determines if the specified user is exempt from spam checks
  def self.is_temporarily_exempt_from_spam_checks?(login:)
    Spam::Kv.store.get("#{SPAM_EXEMPTION_KEY}:#{login}").value { nil } == "1"
  end

  # Public: Indicates if we should delay the processing of the `UserDelete` job for this user
  #         to allow us to perform spam checks. This basically sees if they have recently created
  #         content before trying to delete their account.
  #         See https://github.com/github/code-intelligence-ktlo/issues/1072.
  #
  # Returns a Boolean.
  def delay_deletion_for_spam_checks?
    return false unless GitHub.spamminess_check_enabled?
    return false if is_enterprise_managed?
    return false unless GitHub.flipper[:delay_user_deletion_for_spam_checks].enabled?(self)

    Spam::UserGeneratedContent.has_recently_updated_content_on_any_table?(DELETION_DELAY_TABLES, id)
  end

  private

  def clear_spam_flag_if_allowlisted
    if spammy && never_spammy?
      self.spammy = false
    end
    true
  end

  # This is an after_commit workaround that can be removed after
  # creating a User::Creator service class.
  #
  # See https://github.com/github/github/pull/31471#issuecomment-52836753
  def mark_for_spam_check
    @needs_spam_check = true if new_record?
    true # for good measure
  end

  # Enqueues a job that runs #check_for_spam on this record.
  def enqueue_check_for_spam
    spam_attributes_changed = previous_changes.include?("login")
    return unless @needs_spam_check || spam_attributes_changed
    CheckForSpamJob.enqueue(self, {})
  end

  def set_spammy_notice
    GlobalNoticeNext.new(viewer: self).set_notice(:spammy) if spammy?
  end

  def invalidate_pages_protected_domains
    if self.spammy?
      Pages::InvalidateSpammyUsersPendingDomainsJob.perform_later(self)
    end
  end
end
