# typed: true
# frozen_string_literal: true

class PagesPropagateHttpsRedirectJob < ApplicationJob
  queue_as do
    Page.page_queue.to_s
  end

  def perform(user_id)
    user = User.find_by(id: user_id)
    with_write { user.propagate_https_redirect } if user
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
end
