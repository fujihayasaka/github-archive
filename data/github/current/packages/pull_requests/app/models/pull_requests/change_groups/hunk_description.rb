# typed: true
# frozen_string_literal: true

module PullRequests
  module ChangeGroups
    # Interface for objects that describe a hunk
    # TODO: Update `ChangeGroups::PromptBuilder` to use this interface
    #       currently it has a direct dependency on CCR code, which we could decouple
    module HunkDescription
      extend T::Helpers
      interface!

      sig { abstract.returns(String) }
      def file_path; end

      sig { abstract.returns(GitHub::Diff::Line) }
      def header; end

      sig { abstract.returns(T::Array[GitHub::Diff::Line]) }
      def lines; end
    end
  end
end
