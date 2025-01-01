# typed: false
# frozen_string_literal: true

module GitHub
  module MimeTypeHelpers
    MEDIA_TYPE_RE = %r{([-\w.+]+)/([-\w.+]*)}o
    UNREG_RE      = %r{[Xx]-}o

    # This is a port from the mime-types gem used to mirror the results
    # of the system prior to moving to mini_mime. The original method
    # was defined here: https://github.com/github/mime-types/blob/master/lib/mime/types.rb#L291
    #
    # For more reference PR: https://github.com/github/github/pull/115244
    def self.simplified(mime_info)
      return unless content_type = mime_info&.content_type

      matchdata = MEDIA_TYPE_RE.match(content_type)
      media_type = matchdata.captures[0].downcase.gsub(UNREG_RE, "")
      subtype = matchdata.captures[1].downcase.gsub(UNREG_RE, "")

      "#{media_type}/#{subtype}"
    end
  end
end
