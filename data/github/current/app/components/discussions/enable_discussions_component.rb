# typed: true
# frozen_string_literal: true

module Discussions
  class EnableDiscussionsComponent < ApplicationComponent
    attr_reader :discussions_settings_path

    def initialize(discussions_settings_path:)
      @discussions_settings_path = discussions_settings_path
    end
  end
end
