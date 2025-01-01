# typed: true
# frozen_string_literal: true

module Repositories
  class ContributorFooterComponent < ApplicationComponent
    include ResilienceHelper

    # repo - a Repository
    # safe_link_data_attrs - optional String of HTML-safe Hydro data attributes for the links
    def initialize(repo:, safe_link_data_attrs: nil)
      @repo = repo
      @safe_link_data_attrs = safe_link_data_attrs
    end

    private

    attr_reader :repo, :safe_link_data_attrs

    def render?
      repo.present? && !GitHub.enterprise?
    end

    def any_preferred_files?
      with_database_error_fallback(fallback: false) do
        [contributing_file, code_of_conduct_file, security_policy_file].any?(&:present?)
      end
    end

    memoize def contributing_file
      repo.preferred_files.fetch(:contributing)&.permalink
    end

    memoize def code_of_conduct_file
      repo.preferred_files.fetch(:code_of_conduct)&.permalink
    end

    memoize def security_policy_file
      repo.preferred_files.fetch(:security)&.permalink
    end
  end
end
