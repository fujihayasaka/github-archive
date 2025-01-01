# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class FeedbackLink

    include GitHub::Memoizer

    PRIVATE_FEEDBACK_PHASES = T.let([:alpha, :private_beta].freeze, T::Array[Symbol])

    sig { params(actor: User, scope: T.any(Repository, Organization, Business), phase: Symbol).void }
    def initialize(actor:, scope:, phase: :ga)
      raise ArgumentError, "Invalid phase: #{phase}" unless Phase::VALID_PHASES.include?(phase)
      @phase = phase
      @actor = actor
      @scope = scope
    end

    sig { returns(String) }
    def text
      if url == public_feedback_url
        "Give feedback"
      else
        "Get updates and share feedback"
      end
    end

    sig { returns(T.nilable(String)) }
    def url
      if PRIVATE_FEEDBACK_PHASES.include?(@phase)
        private_feedback_url
      else
        private_feedback_url || public_feedback_url
      end
    end

    private

    sig { returns(T.nilable(String)) }
    memoize def private_feedback_url
      return unless FeatureFlagHelper.in_private_beta?(@actor, @scope)

      repo = private_feedback_repo # https://sorbet.org/docs/flow-sensitive#limitations-of-flow-sensitivity
      return unless repo&.readable_by?(@actor, include_child_teams: true)

      urls.discussions_path(repo.owner, repo)
    end

    sig { returns(T.nilable(Repository)) }
    memoize def private_feedback_repo
      return unless GitHub.dotcom_request?
      Repository.nwo("github-early-access/security-overview-private-beta-community", search_redirects: true)
    end

    sig { returns(String) }
    memoize def public_feedback_url
      urls.org_discussions_category_url("community", :"code-security", host: GitHub.dotcom_host_name, protocol: GitHub.dotcom_host_protocol)
    end

    sig { returns(UrlHelpers) }
    memoize def urls
      T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
    end
  end
end
