# typed: true
# frozen_string_literal: true

class Hook::Event::PageBuildEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Pages site built."

  event_attr :page_build_id, required: true

  def page_build
    @page_build ||= Page::Build.find(page_build_id)
  end

  def target_repository
    page_build.page && page_build.repository
  end

  def actor
    page_build.pusher
  end

  def deliverable?
    target_repository.present?
  end

end
