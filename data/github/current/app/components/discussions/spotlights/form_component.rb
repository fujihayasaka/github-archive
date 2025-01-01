# typed: strict
# frozen_string_literal: true

module Discussions
  module Spotlights
    class FormComponent < ApplicationComponent
      extend T::Sig

      # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
      sig { params(spotlight: DiscussionSpotlight, org_param: T.nilable(String)).void }
      def initialize(spotlight:, org_param: nil)
        @spotlight = spotlight
        @org_param = org_param
      end

      private

      sig { returns(DiscussionSpotlight) }
      attr_reader :spotlight

      sig { returns(T.nilable(String)) }
      attr_reader :org_param

      sig { returns(String) }
      def close_dialog_id
        spotlight.persisted? ? "discussion-edit-spotlight" : "discussion-create-spotlight"
      end

      sig { returns(String) }
      def submit_text
        spotlight.persisted? ? "Save" : "Pin discussion"
      end

      sig { returns(T.nilable(Repository)) }
      memoize def current_repository
        T.must(spotlight.discussion).repository
      end
    end
  end
end
