# typed: strict
# frozen_string_literal: true

module Repositories
  module Error

    class SignatureError < StandardError; end
    class VisibilityLocked < StandardError; end

  end
end
