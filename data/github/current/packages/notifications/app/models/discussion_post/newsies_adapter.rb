# typed: true
# frozen_string_literal: true

# This module implements methods expected (often without clear interface specification) by Newsies.
module DiscussionPost::NewsiesAdapter
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { DiscussionPost }

  # Newsies::Emails::Message assumes this exists.
  sig { returns String }
  def message_id
    "<#{team&.name_with_display_owner}/discussions/#{number}@#{GitHub.urls.host_name}>"
  end

  # Newsies::Emails::Message assumes this exists.
  sig { params(include_host: T::Boolean).returns(String) }
  def permalink(include_host: true)
    # FIXME: This needs to point to a real permalink not a fragment.
    "#{team&.permalink(include_host: include_host)}/discussions/#{number}"
  end
end
