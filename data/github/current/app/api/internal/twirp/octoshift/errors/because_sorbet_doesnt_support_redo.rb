# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Errors

    # Public: Used for retrying because Sorbet doesn't support redo (https://sorbet.org/docs/error-reference#3003).
    class BecauseSorbetDoesntSupportRedo < StandardError
    end
  end
end
