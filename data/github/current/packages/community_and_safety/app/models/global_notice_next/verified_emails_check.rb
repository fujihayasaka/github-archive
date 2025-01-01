# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class VerifiedEmailsCheck < BaseCheck
    def should_show_notice?
      return false unless viewer.should_verify_email?

      if !viewer.joined_too_recently_for_email_verification_reminder?
        UserSignupFollowupJob.perform_later(viewer)
      end

      true
    end
  end
end
