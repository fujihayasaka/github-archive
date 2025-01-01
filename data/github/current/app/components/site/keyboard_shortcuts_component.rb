# typed: true
# frozen_string_literal: true

class Site::KeyboardShortcutsComponent < ApplicationComponent
  include UrlHelper
  include KeyboardShortcutsHelper

  def initialize(user:, contexts: nil)
    @user = user
    @contexts = contexts.to_s.split(",")
  end

  def shortcuts(scope)
    keyboard_shortcuts_for(@user, scope, contexts)
  end

  def title_for(scope)
    KeyboardShortcutsHelper::DEFAULT_KEYBOARD_SHORTCUTS_TITLES[scope]
  end

  def contexts
    @contexts
  end
end
