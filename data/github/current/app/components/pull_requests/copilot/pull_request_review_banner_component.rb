# typed: strict
# frozen_string_literal: true

class PullRequests::Copilot::PullRequestReviewBannerComponent < ApplicationComponent
  extend T::Sig
  include ApplicationComponent::Rescuable

  rescue_from_database_errors with: :nothing

  VALID_LOCATIONS = T.let(%w(compare conversation files_changed).freeze, T::Array[String])

  sig do
    params(
      viewer: T.nilable(User),
      copilot_user: T.nilable(Copilot::User),
      pull_request: T.nilable(PullRequest),
      comparison: T.nilable(T.any(GitHub::Comparison, PullRequest::Comparison))
    ).returns(T::Boolean)
  end
  def self.render?(viewer:, copilot_user: nil, pull_request: nil, comparison: nil)
    return false if GitHub.enterprise? # the #copilot_pull_request_review_banner_path route doesn't exist on GHES
    return false if viewer.nil? || !viewer.feature_enabled?(:copilot_reviews)
    return false if pull_request && comparison && pull_request != comparison.pull

    base_sha = head_sha = nil

    if pull_request
      return false if pull_request.closed?
      return false unless viewer.id == pull_request.user_id
      return false if pull_request.base_repository.nil?

      head_sha = pull_request.head_sha
      base_sha = pull_request.base_sha
      comparison ||= pull_request.comparison
    else
      return false if comparison.nil?

      if comparison.is_a?(GitHub::Comparison)
        return false if comparison.base_repo.nil?

        head_sha = comparison.head_sha
        base_sha = comparison.base_sha
      else # PullRequest::Comparison
        return false if comparison.pull.nil? || comparison.pull.base_repository.nil?

        head_sha = comparison.pull.head_sha
        base_sha = comparison.pull.base_sha
      end
    end

    return false if head_sha.nil? || base_sha.nil?
    return false if diff_lines_changed(comparison).zero?

    copilot_user ||= Copilot::User.new(viewer)
    copilot_user.dotcom_chat_enabled?
  end

  sig { params(comparison: T.any(GitHub::Comparison, PullRequest::Comparison)).returns(Integer) }
  def self.diff_lines_changed(comparison)
    diff = T.let(comparison.diffs, GitHub::Diff)
    diff.changes
  rescue GitRPC::Error => e
    Failbot.report(e)
    0
  end

  sig do
    params(
      pull_request: T.nilable(PullRequest),
      comparison: T.nilable(T.any(GitHub::Comparison, PullRequest::Comparison)),
      location: T.nilable(Symbol)
    ).void
  end
  def initialize(pull_request: nil, comparison: nil, location: nil)
    @pull_request = pull_request
    @comparison = comparison
    @location = T.let(location ? fetch_or_fallback(VALID_LOCATIONS, location.to_s, nil) : nil, T.nilable(String))
  end

  private

  # Private: Whether the component should render. Keep checks in this method in sync with
  # `shouldRenderBannerForPullRequest` in # ui/packages/copilot-pr-review-banner/use-load-tree-comparison.ts that
  # determines when we should use the pull request information to render the CopilotPrReviewBanner React component.
  # Logic in # `shouldRenderBannerForPullRequest` affects when the pre-review banner is shown on React'ified pull
  # request pages behind the `prx` feature flag. Logic here in #render? affects when the pre-review banner is shown on
  # non-React'ified pull request pages.
  sig { returns T::Boolean }
  def render?
    should_render = self.class.render?(viewer: current_user, copilot_user: current_copilot_user,
      pull_request: @pull_request, comparison: @comparison)
    return false unless should_render
    instrument_view
    true
  end

  sig { returns String }
  def fragment_src
    copilot_pull_request_review_banner_path(
      base_repository.owner_display_login,
      base_repository.name,
      base_sha: base_sha,
      head_sha: head_sha,
      head_repo_id: head_repo_id_param,
      thread_name: thread_name,
      location: @location,
      channel: signed_websocket_channel,
      files_excluded: files_excluded? ? "1" : nil,
    )
  end

  sig { returns T::Boolean }
  def files_excluded?
    copilot_content_exclusion = get_copilot_content_exclusion_rules(comparison.repo.owner)
    diffs = comparison.diffs

    filtered_diffs = PullRequests::Copilot::DiffsFilter.new(diffs: diffs, copilot_content_exclusion: copilot_content_exclusion)
    filtered_diffs.count != diffs.changed_files
  end

  sig { params(owner: User).returns(T.nilable(T::Array[T.nilable(String)])) }
  def get_copilot_content_exclusion_rules(owner)
    return unless owner.is_a?(Organization) && ::Copilot::ContentExclusion.is_available?(owner)

    target = base_repository.fork? ? base_repository.parent || base_repository : base_repository

    ::Copilot::ContentExclusion
      .rules_for_repo(target)
      .flat_map { |_config, rules| rules.collect { _1.patterns.map { |path| path[0] == "/" ? path[1..-1] : path } } }
      .flatten.uniq
  end

  sig { returns T::Boolean }
  def cross_repository?
    comparison = self.comparison
    if comparison.is_a?(GitHub::Comparison)
      comparison.cross_repository?
    else # PullRequest::Comparison
      comparison.pull.cross_repo?
    end
  end

  sig { returns T.any(GitHub::Comparison, PullRequest::Comparison) }
  memoize def comparison
    return @comparison if @comparison
    pull = T.must_because(@pull_request) { "#render? ensures PR was given if no comparison was given" }
    pull.comparison
  end

  sig { returns String }
  def signed_websocket_channel
    signed_websocket_channel_for_branch ||
      GitHub::WebSocket::Channels.signed_pull_request(@pull_request || comparison.pull)
  end

  sig { returns T.nilable(String) }
  def signed_websocket_channel_for_branch
    comparison = self.comparison
    if comparison.is_a?(GitHub::Comparison)
      repo = cross_repository? ? comparison.head_repo : base_repository
      GitHub::WebSocket::Channels.signed_branch(repo, comparison.display_head_ref)
    end
  end

  sig { returns T.nilable(String) }
  memoize def base_sha
    comparison = self.comparison
    if comparison.is_a?(GitHub::Comparison)
      comparison.base_sha
    else # PullRequest::Comparison
      comparison.pull.base_sha
    end
  end

  sig { returns T.nilable(String) }
  memoize def head_sha
    comparison = self.comparison
    if comparison.is_a?(GitHub::Comparison)
      comparison.head_sha
    else # PullRequest::Comparison
      comparison.pull.head_sha
    end
  end

  sig { returns Repository }
  memoize def base_repository
    comparison = self.comparison
    if comparison.is_a?(GitHub::Comparison)
      comparison.base_repo
    else # PullRequest::Comparison
      comparison.pull.base_repository
    end
  end

  sig { returns String }
  def thread_name
    PullRequests::Copilot::CodeReviewThreadNameGenerator.call(
      pull_request: @pull_request,
      comparison: @comparison,
    )
  end

  sig { returns T.nilable(Integer) }
  memoize def head_repo_id_param
    # Don't need to pass the head repository ID to the banner endpoint if it's the same as the base repository's
    return unless cross_repository?

    comparison = self.comparison
    if comparison.is_a?(GitHub::Comparison)
      comparison.head_repo.id
    else # PullRequest::Comparison
      comparison.pull.head_repository_id
    end
  end

  sig { void }
  def instrument_view
    GlobalInstrumenter.instrument("copilot.pull_request.pre_review.banner_view",
      analytics_tracking_id: current_user.analytics_tracking_id,
      diff_lines_changed: self.class.diff_lines_changed(comparison),
    )
  end
end
