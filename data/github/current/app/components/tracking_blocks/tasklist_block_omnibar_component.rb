# typed: true
# frozen_string_literal: true
require "securerandom"

module TrackingBlocks
  class TasklistBlockOmnibarComponent < ApplicationComponent
    include GitHub::Memoizer

    attr_reader :current_item_display_number,
      :current_owner_login,
      :current_repository_name,
      :tasklist_block_markdown_at_rest_enabled,
      :tasklist_block_id,
      :title

    def initialize(
      render_context:,
      tasklist_block_id: SecureRandom.uuid,
      options: {},
      title: nil
    )
      @current_item_display_number = render_context.current_item_display_number
      @current_repository_name = render_context.current_repository_name
      @current_owner_login = render_context.current_owner_login
      @tasklist_block_id = tasklist_block_id.to_s
      @tasklist_block_markdown_at_rest_enabled = options.fetch(:tasklist_block_markdown_at_rest_enabled, false)
      @title = title
    end

    # Public: returns the uuid of the item if exists, otherwise it returns a
    # memoized (and therefore stable) uuid. In practice this is heplful for
    # creating a unique id for the input element, easing accessibility concerns.
    sig { returns(String) }
    memoize def input_uuid
      @tasklist_block_id || SecureRandom.uuid
    end
  end
end
