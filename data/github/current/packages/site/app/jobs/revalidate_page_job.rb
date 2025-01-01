# typed: true
# frozen_string_literal: true

class RevalidatePageJob < ApplicationJob
  queue_as :site_contentful

  retry_on_dirty_exit

  # jobs for the same page and options will be throttled for ten minutes
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  def perform(page_klass, options = {})
    page_klass.new(**options).revalidate
  end
end
