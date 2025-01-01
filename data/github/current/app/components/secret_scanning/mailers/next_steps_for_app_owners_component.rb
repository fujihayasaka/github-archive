# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class NextStepsForAppOwnersComponent < ApplicationComponent
      extend T::Sig

      sig do
        params(
          review_link_text: String,
          review_url: String,
          apps_docs_link_text: String,
          apps_docs_url: String,
        ).void
      end
      def initialize(review_link_text:, review_url:, apps_docs_link_text:, apps_docs_url:)
        @review_link_text = review_link_text
        @review_url = review_url
        @apps_docs_link_text = apps_docs_link_text
        @apps_docs_url = apps_docs_url
      end
    end
  end
end
