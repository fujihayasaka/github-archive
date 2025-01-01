# typed: true
# frozen_string_literal: true
module Comments
  class DeferredEditFormComponent < ApplicationComponent
    attr_reader :src

    def initialize(form_path:, comment_context:, textarea_id:)
      @src = "#{form_path}/edit_form?textarea_id=#{ERB::Util.url_encode(textarea_id)}&comment_context=#{ERB::Util.url_encode(comment_context)}"
    end
  end
end
