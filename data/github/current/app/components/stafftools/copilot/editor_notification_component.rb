# typed: true
# frozen_string_literal: true

class Stafftools::Copilot::EditorNotificationComponent < ApplicationComponent
  attr_reader :editor_notifications

  def initialize(editor_notifications)
    @editor_notifications = editor_notifications
  end

  def render?
    @editor_notifications.any?
  end
end
