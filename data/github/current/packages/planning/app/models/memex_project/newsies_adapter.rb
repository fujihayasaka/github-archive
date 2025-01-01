# typed: strict
# frozen_string_literal: true

# This module implements methods expected by Newsies.
module MemexProject::NewsiesAdapter
  include Notifications::SubscribableThread

  extend T::Helpers
  extend T::Sig

  requires_ancestor { MemexProject }

  sig { returns(Promise[MemexProject::MemexOwner]) }
  def async_notifications_list
    async_owner.then do |owner|
      owner || User.ghost
    end
  end

  sig { returns(T.nilable(User)) }
  def notifications_author
    creator
  end

  sig { returns(T.self_type) }
  def notifications_thread
    self
  end
end
