# typed: true
# frozen_string_literal: true

module Twirp
  module Encoding

    # In Twirp 1.7.2 the default behaviour of emitting defaults only in strict mode
    # was changed so that defaults are emitted in all modes. This patch restores
    # the previous behaviour so that we can track our clients as they become
    # compatible with strict mode by adding the "strict=true" to their headers.
    #
    # See https://github.com/twitchtv/twirp-ruby/commit/9f82040807832b34093f02db449a3d5fa5ef92d4
    def self.encode(msg_obj, msg_class, content_type)
      case content_type
      when JSON then msg_class.encode_json(msg_obj, emit_defaults: false)
      when JSON_STRICT then msg_class.encode_json(msg_obj, emit_defaults: true)
      when PROTO then msg_class.encode(msg_obj)
      else raise ArgumentError.new("Invalid content_type")
      end
    end
  end
end
