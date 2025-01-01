# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeBox
    class CombinedBranchStatusComponent < ApplicationComponent
      extend T::Sig
      include ApplicationComponent::Rescuable

      rescue_from_database_errors do
        T.bind(self, CombinedBranchStatusComponent)
        render "statuses/combined_branch_status_unavailable"
      end

      sig { returns(MergeButtonView) }
      attr_reader :merge_button_view

      sig { params(merge_button_view: MergeButtonView).void }
      def initialize(merge_button_view)
        @merge_button_view = merge_button_view
      end
    end
  end
end
