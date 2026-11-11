# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserAttachmentsOrderField < Platform::Enums::Base
      description "Properties by which user attachments connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Allows ordering a list of attachments by the `created_at` value.", value: "created_at"
    end
  end
end
