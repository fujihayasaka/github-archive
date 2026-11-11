# typed: false
# frozen_string_literal: true

class CommunityProfile < ApplicationRecord::Domain::Repositories
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  include ActionView::Helpers::TagHelper

  validates :repository_id, uniqueness: true

  UPDATE_INTERVAL = 10.minutes.to_i

  # Internal: Enqueue job to update help wanted counter columns
  #
  # returns boolean
  def self.enqueue_help_wanted_job(repository)
    return false if GitHub.enterprise?

    CommunityProfileUpdateHelpWantedCountersJob.enqueue_once_per_interval(args: [repository.id], interval: UPDATE_INTERVAL)
  end

  def self.eligible_repository?(repository)
    repository.public? && !repository.fork?
  end

  # File types whose preferred-file lookups are warmed in parallel before
  # health_percentage evaluates the sync metric predicates. This avoids N+1
  # sequential spokesd RPCs for file types that go through
  # Repository#preferred_file (code_of_conduct, contributing, license, readme,
  # security_policy, and pull_request_template). Note: issue_template? uses a
  # separate path (Repository#preferred_issue_templates) that is NOT covered
  # by this cache warming.
  HEALTH_FILE_TYPES = %i[
    code_of_conduct
    contributing
    license
    readme
    security
    issue_template
    pull_request_template
  ].freeze

  def health_percentage(viewer = nil)
    parallel = parallel_health_check_enabled?

    # Wrap the entire method so the metric captures both the parallel warming
    # (when enabled) and the predicate evaluation. This gives an apples-to-
    # apples A/B comparison: parallel=false includes sequential spokesd calls
    # in the predicates, parallel=true includes the Promise.all warming +
    # fast cached predicate evaluation.
    GitHub.dogstats.distribution_time(
      "community_profile.health_percentage",
      tags: ["parallel_warming:#{parallel}"],
    ) do
      # Warm the preferred-file cache in parallel when the feature flag is on.
      # async_preferred_file memoizes each resolved value so subsequent sync
      # calls to preferred_file return the cached result without additional
      # spokesd RPCs.
      if parallel && repository
        promises = HEALTH_FILE_TYPES.map { |type| repository.async_preferred_file(type) }
        Promise.all(promises).sync
      end

      # Evaluate the sync predicates. When parallel warming ran, most hit the
      # warm cache; issue_template? goes through preferred_issue_templates
      # regardless.
      metrics = health_metrics(viewer)
      (metrics.count { |metric| !!public_send(metric) }.to_f / metrics.count * 100).to_i
    end
  end

  def health_metrics(viewer = nil)
    metrics = [
      :sufficient_code_of_conduct?,
      :contributing?,
      :license?,
      :readme?,
      :description?,
      :pr_or_issue_template?,
      :security_policy?,
    ]

    if repo_supports_tiered_reporting?
      metrics << :tiered_reporting_enabled?
    end

    metrics
  end

  # only used in app/api/serializer/repositories_dependency.rb for API now, no longer used at all in community profile
  def code_of_conduct
    CodeOfConduct.detect(repository)
  end

  def sufficient_code_of_conduct?
    @sufficient_code_of_conduct ||= sufficient_code_of_conduct
  end

  def async_sufficient_code_of_conduct?
    async_contents_when_file_exists("code_of_conduct").then do |coc|
      next false unless coc&.present?
      Regexp.union(ignored_cocs).match(coc.data).nil?
    end
  end

  def docs?
    !!documentation_url
  end

  def description?
    return false unless repository
    !!repository.description
  end

  def pr_or_issue_template?
    !!(issue_template? || pr_template)
  end

  def async_pr_or_issue_template?
    async_contents_when_file_exists("issue_template").then do |issue|
      next true if issue
      async_contents_when_file_exists("pull_request_template").then do |pr|
        !!pr
      end
    end
  end

  def code_of_conduct?
    !!contents_when_file_exists("code_of_conduct")
  end

  def async_code_of_conduct?
    async_contents_when_file_exists("code_of_conduct").then { |val| !!val }
  end

  def contributing?
    !!contents_when_file_exists("contributing")
  end

  def async_contributing?
    async_contents_when_file_exists("contributing").then { |val| !!val }
  end

  def license?
    !!contents_when_file_exists("license")
  end

  def async_license?
    async_contents_when_file_exists("license").then { |val| !!val }
  end

  def readme?
    !!contents_when_file_exists("readme")
  end

  def async_readme?
    async_contents_when_file_exists("readme").then { |val| !!val }
  end

  def security_policy?
    !!contents_when_file_exists("security_policy")
  end

  def async_security_policy?
    async_contents_when_file_exists("security_policy").then { |val| !!val }
  end

  def tiered_reporting_enabled?
    repository&.tiered_reporting_explicitly_enabled?
  end

  def reactable?
    false
  end

  def documentation_url
    return unless repository
    return repository.homepage if repository.homepage.present?
    return repository.gh_pages_url if repository.has_gh_pages?
    (repository.permalink + "/tree/master/docs") if repository.includes_directory?("docs")
  end

  def issue_template
    contents_when_file_exists("issue_template")
  end

  def issue_template?
    return false unless repository
    repository.preferred_issue_templates.templates.any? { |template| !template.body.blank? }
  end

  def pr_template
    contents_when_file_exists("pull_request_template")
  end

  def has_issue_from_non_collaborator?
    return unless repository
    collaborators = repository.member_ids
    Issue.select("id, user_id").where(repository_id: repository.id).find_in_batches(batch_size: 500) do |batch| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return true if (batch.map(&:user_id).uniq - collaborators).any?
    end
    false
  end

  def has_outside_contribution?
    return unless repository
    (repository.contributor_ids - repository.all_member_ids).any?
  end

  private

  def repo_supports_tiered_reporting?
    return false unless GitHub.can_report?
    repository&.eligible_for_tiered_reporting?
  end

  def parallel_health_check_enabled?
    return false unless repository
    FeatureFlag.vexi.enabled?(:community_profile_parallel_health_check, repository, default: false)
  end

  def ignored_cocs
    [
        /no code of conduct/i,
        /This project adheres to No Code of Conduct/i,
    ]
  end

  def sufficient_code_of_conduct
    coc = contents_when_file_exists("code_of_conduct")
    return false unless coc&.present?
    Regexp.union(ignored_cocs).match(coc.data).nil? # we want the regexes to fail!
  end

  def contents_when_file_exists(file)
    return nil if repository.nil?
    file_contents = repository.send("preferred_#{file}")
    file_contents if file_contents && file_contents.data.present?
  end

  # Map community profile file names to PreferredFile type symbols.
  # Most names map directly, but security_policy -> :security.
  FILE_TO_TYPE = {
    "code_of_conduct"        => :code_of_conduct,
    "contributing"           => :contributing,
    "license"                => :license,
    "readme"                 => :readme,
    "security_policy"        => :security,
    "issue_template"         => :issue_template,
    "pull_request_template"  => :pull_request_template,
  }.freeze

  def async_contents_when_file_exists(file)
    return Promise.resolve(nil) if repository.nil?
    type = FILE_TO_TYPE[file]
    if type
      repository.async_preferred_file(type).then do |file_contents|
        next unless file_contents
        file_contents.async_data.then do |data|
          next file_contents if data.present?
        end
      end
    else
      # Fallback to dynamic dispatch for unmapped types
      repository.public_send("async_preferred_#{file}").then do |file_contents|
        next unless file_contents
        file_contents.async_data.then do |data|
          next file_contents if data.present?
        end
      end
    end
  end

  def not_a_collaborator?(user_id)
    !repository.member_ids.include?(user_id)
  end
end
