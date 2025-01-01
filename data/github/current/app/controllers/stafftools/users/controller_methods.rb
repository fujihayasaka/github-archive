# typed: true
# frozen_string_literal: true

module Stafftools::Users::ControllerMethods
  include StafftoolsHelper
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { StafftoolsController }

  USER_SORT_LABELS = {
    "alphanumerically" => "login ASC",
    "newest" => "created_at DESC",
    "oldest" => "created_at ASC",
  }.freeze

  included do
    T.bind(self, T.class_of(StafftoolsController))
    helper_method :users_sort_labels
    helper_method :user_sort_order
  end

  def fetch_error_states
    is_user = this_user.user?
    verified_emails = this_user.emails.user_entered_emails.verified
    has_keys = !this_user.public_keys.count.zero?

    @error_states = {
      spammy: this_user.spammy?,
      suspended: this_user.suspended? || this_user.sdn_suspended?,
      no_primary_email: is_user && !this_user.has_primary_email?,
      no_verified_email: GitHub.email_verification_enabled? && is_user && verified_emails.count.zero?,
      dupe_email: is_user && this_user.has_duplicate_email?,
      org_transform: is_user && Organization.transforming?(this_user),
      unverified_keys: has_keys && this_user.verified_keys.count.zero?,
      reserved_login: this_user.login_reserved?,
    }

    @spam_flag_timestamp = spam_flag_timestamp(this_user)

    @obfuscated_dupe_emails = if GitHub.enterprise?
      0
    else
      GitHub::SpamChecker.count_obfuscated_duplicate_emails(this_user)
    end
  end

  def user_query(extra = nil)
    {
      order: users_sort_labels.fetch(user_sort_order, "created_at DESC"),
      page: current_page,
      conditions: [
        ["login != ?", "type = 'User'", extra].compact.join(" AND "),
        [GitHub.ghost_user_login],
      ],
    }
  end

  def users_sort_labels
    USER_SORT_LABELS
  end

  def user_sort_order
    @_user_sort_order ||= if users_sort_labels.keys.include?(params[:sort])
      params[:sort]
    else
      users_sort_labels.keys.first
    end
  end

  def paginate(scope, query)
    scope.order(query[:order]).where(*query[:conditions]).page(query[:page])
  end
end
