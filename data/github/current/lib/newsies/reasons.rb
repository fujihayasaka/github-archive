# typed: true
# frozen_string_literal: true

module Newsies
  module Reasons
    # Reasons that must never override an existing reason for a thread subscription.
    #
    # These are reasons that we think are lower priority than the other reasons in the
    # `Participating` list below. As a result, these reasons will never override an existing reason
    # that someone is subscribed to a thread. Conversely, reasons that are not in this list can be
    # used to replace ones that are.
    LowPriority = Set.new([:team_mention, :comment, :manual, :push, :review_requested])

    # If you get a notification with one of these reasons, it will bust the
    # mute setting on that thread.  Emails will use CC instead of BCC
    Participating = LowPriority + [:author, :mention, :assign, :state_change, :your_activity, :security_advisory_credit]

    Vulnerability = :security_alert

    ContinuousIntegration = :ci_activity
    ApprovalRequested = :approval_requested

    # Converts the given reason string to a standardized set of reasons as
    # stored in the database.
    #
    # reason - String name of the Subscription reason.
    #
    # Returns a Symbol.
    def valid_reason_from(reason)
      case reason.to_s
      when /\Acomment/                                         then :comment
      when /\Aauthor/                                          then :author
      when /\Amention/                                         then :mention
      when /\Ateam/                                            then :team_mention
      when /\Aassign/                                          then :assign
      when /\Areview_requested/                                then :review_requested
      when /\Asecurity_alert/                                  then :security_alert
      when /\Asecurity_advisory_credit/                        then :security_advisory_credit
      when /\Amanual/                                          then :manual
      when /\A(closed|(re)?open|merge)/                        then :state_change
      when /\Astate_change/                                    then :state_change
      when /\Apush/                                            then :push
      when /\Aready_for_review/                                then :ready_for_review
      when /\Aci_activity/                                     then :ci_activity
      when /\Aapproval_requested/                              then :approval_requested
      when /\Alist/, /\Athread_type/, /\Adomain_subscription/  then :subscribed
      when /\Amember_feature_requested/                        then :member_feature_requested
      end
    end
    module_function :valid_reason_from
  end
end
