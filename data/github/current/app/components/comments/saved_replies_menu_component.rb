# typed: true
# frozen_string_literal: true
module Comments
  class SavedRepliesMenuComponent < ApplicationComponent
    attr_reader :filter_field_id, :textarea_id, :saved_reply_context

    def initialize(
      textarea_id:,
      saved_reply_context: nil
    )
      @filter_field_id = "saved-reply-filter-field-#{SecureRandom.hex(4)}"
      @textarea_id = textarea_id
      @saved_reply_context = saved_reply_context || "none" # Allows us to handle nils coming in from the args
    end
  end
end
