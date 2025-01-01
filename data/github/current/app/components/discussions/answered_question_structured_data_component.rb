# typed: true
# frozen_string_literal: true

module Discussions
  # Implements the QAPage structured data for use via google search.
  # https://developers.google.com/search/docs/appearance/structured-data/qapage
  class AnsweredQuestionStructuredDataComponent < ApplicationComponent
    include ViewComponent::InlineTemplate
    extend T::Sig

    erb_template <<~ERB
      <%= structured_data_script_tag %>
    ERB

    sig { returns(Discussion) }
    attr_reader :discussion

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig { params(timeline: DiscussionTimeline, org_param: T.nilable(String)).void }
    def initialize(timeline, org_param: nil)
      @timeline = timeline
      @discussion = timeline.discussion
      @org_param = org_param
    end

    private

    sig { returns T.nilable(String) }
    attr_reader :org_param

    # To be eligible, a discussion must have an answer.
    def render?
      discussion.answered?
    end

    def structured_data_script_tag
      @structured_data = {
        "@context": "https://schema.org",
        "@type": "QAPage",
        "mainEntity":
          {
            "@type": "Question",
            "name": discussion.title,
            "text": discussion.body_html,
            "upvoteCount": discussion.total_upvotes,
            "answerCount": discussion.direct_comment_count,
            "acceptedAnswer": {
              "@type": "Answer",
              "text": T.must(timeline.selected_answer).body_html,
              "upvoteCount": T.must(timeline.selected_answer).total_upvotes,
              "url": agnostic_discussion_url(discussion, org_param: org_param,
                anchor: T.must(discussion.chosen_comment).dom_id),
            }
          }
      }
      content_tag(:script, @structured_data.to_json, { type: "application/ld+json" }, false)
    end
  end
end
