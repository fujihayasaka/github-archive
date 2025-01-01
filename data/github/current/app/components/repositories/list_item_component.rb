# typed: true
# frozen_string_literal: true

module Repositories
  class ListItemComponent < ApplicationComponent
    include ApplicationHelper
    include GraphsHelper
    include StacksHelper
    include ::CacheHelper
    include ::TextHelper

    def initialize(
      repository:,
      organization: nil,
      is_registry_enabled:,
      responsive: false,
      pull_request_count: nil,
      issue_count: nil,
      network_count: nil,
      topic_names: nil,
      skip_details: false,
      **args
    )
      @repository = repository
      @organization = organization
      @is_registry_enabled = is_registry_enabled
      @responsive = responsive
      @pull_request_count = pull_request_count
      @issue_count = issue_count
      @topic_names = topic_names
      @network_count = network_count
      @skip_details = skip_details
      @args = args
    end

    private

    def render?
      repository.present?
    end

    def pull_request_count
      count = @pull_request_count || repository.open_pull_request_count_for(current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      capped_number_with_delimiter(count, limit: 5_000)
    end

    def issue_count
      count = @issue_count || repository.open_issue_count_for(current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      capped_number_with_delimiter(count, limit: 5_000)
    end

    def issue_count_needing_help
      return unless community_profile

      @issue_count_needing_help ||= if link_to_help_wanted?
        community_profile.help_wanted_issues_count
      elsif link_to_good_first_issue?
        community_profile.good_first_issue_issues_count
      end
    end

    def issues_needing_help_path
      return unless community_profile

      query = if link_to_help_wanted?
        label = repository.help_wanted_label
        "label:\"#{label.name}\""
      elsif link_to_good_first_issue?
        label = repository.good_first_issue_label
        "label:\"#{label.name}\""
      end

      if query
        query += " is:issue is:open"
        issues_path(repository.owner, repository, q: query)
      end
    end

    def community_profile
      repository.community_profile
    end

    def show_issues_needing_help?
      return false unless repository.has_issues?
      link_to_help_wanted? || link_to_good_first_issue?
    end

    def link_to_help_wanted?
      community_profile && community_profile.help_wanted_issues_count > 0 &&
        repository.help_wanted_label
    end

    def link_to_good_first_issue?
      return false if link_to_help_wanted?

      community_profile && community_profile.good_first_issue_issues_count > 0 &&
        repository.good_first_issue_label
    end

    def topic_path(topic)
      qualifiers = ["topic:#{topic}"]
      qualifiers << "fork:true" if repository.fork?
      qualifiers << "org:#{repository.owner}" if repository.owner.organization?
      search_path(q: qualifiers.join(" "), type: "Repositories")
    end

    memoize def topic_names
      @topic_names || repository.topics.limit(7).pluck(:name)
    end

    def show_owner_prefix?
      return false unless organization.present?
      repository.owner != organization
    end

    def type
      RepositoriesTypeHelper.type(
        visibility: repository.visibility,
        mirror: repository.mirror?,
        archived: repository.archived?,
        template: repository.template?,
      )
    end

    def component_class_names
      out = []

      out << (repository.public? ? "public" : "private")
      out << (repository.fork? ? "fork" : "source")
      out << "mirror" if repository.mirror?
      out << "archived" if repository.archived?

      out.join(" ")
    end

    def overview_cache_key
      version = 23
      "orgs:overview:repo:#{version}:#{repository.id}:#{repository.owner}:#{repository.pushed_at.to_i}:#{repository.updated_at.to_i}:#{responsive}"
    end

    def license
      repository.license
    end

    def show_license?
      license && !license.other?
    end

    def license_name
      license.try(:spdx_id)
    end

    def repository_participation_sparkline_cached?
      controller.fragment_exist?(repository_participation_sparkline_cache_key(repository).join(":"))
    end

    def packages_count
      repository.packages.size
    end

    memoize def network_count
      @network_count || repository.network_count
    end

    attr_reader :repository, :organization, :is_registry_enabled, :responsive, :skip_details
  end
end
