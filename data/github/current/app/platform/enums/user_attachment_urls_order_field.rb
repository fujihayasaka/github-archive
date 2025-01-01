# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserAttachmentUrlsOrderField < Platform::Enums::Base
      description "Properties by which user attachment urls connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Allows ordering a list of attachment urls by the `created_at` value.", value: "created_at"
    end
  end
end
