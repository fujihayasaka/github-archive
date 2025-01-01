# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RefOrderField < Platform::Enums::Base
      description "Properties by which ref connections can be ordered."

      value "TAG_COMMIT_DATE", "Order refs by underlying commit date if the ref prefix is refs/tags/", value: :tag_commit_date
      value "ALPHABETICAL", "Order refs by their alphanumeric name", value: :alphabetical
    end
  end
end
