# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class FileViewedState < Platform::Enums::Base
      description "The possible viewed states of a file ."

      value "DISMISSED", "The file has new changes since last viewed.", value: :dismissed
      value "VIEWED", "The file has been marked as viewed.", value: :viewed
      value "UNVIEWED", "The file has not been marked as viewed.", value: :unviewed
    end
  end
end
