# frozen_string_literal: true

require "escape_utils"
EscapeUtils.html_safe_string_class = ActiveSupport::SafeBuffer

class ERB
  module Util
    def force_escape_with_transcoding_guess(s)
      s = String.new(s.to_s) # reset html_safe
      ERB::Util.html_escape(GitHub::Encoding.try_guess_and_transcode(s, context: "force_escape_with_transcoding_guess"))
    end

    def force_escape(s)
      s = String.new(s.to_s) # reset html_safe
      ERB::Util.html_escape(s)
    end
  end
end
