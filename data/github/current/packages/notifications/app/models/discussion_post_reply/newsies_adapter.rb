# typed: true
# frozen_string_literal: true

# This module implements methods expected (often without clear interface specification) by Newsies.
module DiscussionPostReply::NewsiesAdapter
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { DiscussionPostReply }

  # Newsies::Emails::Message assumes this exists.
  sig { returns String }
  def message_id
    "<#{team&.name_with_display_owner}/discussions/#{discussion_post&.number}/comments/#{number}/" +
    "@#{GitHub.urls.host_name}>"
  end

  # Newsies::Emails::Message assumes this exists.
  sig { params(include_host: T::Boolean).returns(String) }
  def permalink(include_host: true)
    "#{discussion_post&.permalink(include_host: include_host)}/comments/#{number}"
  end
end
