# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class FeedbackLinkComponent < ApplicationComponent

    TEST_SELECTOR = "security-center-feedback-link"

    sig { returns(T.untyped) }; attr_accessor :system_arguments
    private :system_arguments

    sig { params(phase: Symbol, actor: User, scope: T.any(Repository, Organization, Business), system_arguments: Primer::SystemArgumentsValue).void }
    def initialize(phase, actor:, scope:, **system_arguments)
      @feedback = T.let(FeedbackLink.new(phase: phase, actor: actor, scope: scope), FeedbackLink)
      @system_arguments = system_arguments
    end

    sig { returns(T::Boolean) }
    def render?
      feedback_url.present?
    end

    private

    sig { returns(String) }
    def feedback_text
      @feedback.text
    end

    sig { returns(T.nilable(String)) }
    def feedback_url
      @feedback.url
    end
  end
end
