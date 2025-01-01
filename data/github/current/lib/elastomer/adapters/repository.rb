# typed: true
# frozen_string_literal: true

require "nokogiri"

module Elastomer::Adapters

  # The Repository adapter is used to transform a repository ActiveRecord
  # object into a Hash document that can be indexed in ElasticSearch.
  #
  class Repository < ::Elastomer::Adapter
    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Repos"
    end

    def self.mysql_cluster
      ::Repository.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= if GitHub.flipper[:repos_domain_elastomer].enabled?
        ::Repositories.domain.by_id(document_id)
      else
        ::Repository.find_by(id: document_id)
      end
    end
    alias :repository :model
    alias :current_repository :model

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    #
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      @hash = nil

      return unless repository.repo_is_searchable?

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        name: repository.name,
        name_sort: repository.name.downcase,
        name_with_owner: repository.name_with_owner,
        description: repository.description,
        readme: readme,
        repo_id: repository.id,
        network_id: repository.network_id,
        license_id: license_id,
        size: repository.disk_usage.to_i,
        forks: repository.public_fork_count.to_i,
        fork: repository.fork?,
        followers: repository.stargazer_count.to_i,
        owner_id: repository.owner_id,
        pushed_at: repository.pushed_at || repository.created_at,
        created_at: repository.created_at,
        updated_at: repository.updated_at,
        public: repository.public?,
        business_id: repository.internal_visibility_business_id,
        visibility: repository.visibility,
        mirror: repository.mirror?,
        template: repository.template?,
        sponsorable: repository.sponsorable_owner?,
        has_funding_file: repository.has_funding_file?,
        archived: repository.archived?,
        # size forces a load of topics, so they are available in memory for next pluck calls.
        # On the other hand, count would return number from DB, so next pluck's would query again.
        num_topics: repository.topics.size,
        applied_topics: repository.topics.pluck(:name),
        ranked_hashtags: ranked_hashtags,
        help_wanted_issues_count: help_wanted_issues_count,
        good_first_issue_issues_count: good_first_issue_issues_count,
      }

      if language = repository.primary_language
        @hash[:language]    = language.linguist_name
        @hash[:language_id] = language.linguist_id
      end

      rank  = 1.0
      rank += Math.log(@hash[:forks])       if @hash[:forks] > 0
      rank += Math.log10(@hash[:followers]) if @hash[:followers] > 0
      rank *= 0.8                           if @hash[:fork]
      @hash[:rank] = rank

      @hash[:custom_property_values] = custom_property_values if custom_property_values

      @hash
    end

    # Helper method that will return the text from the repository preferred
    # readme file. If there is no readme file then `nil` is returned.
    #
    # Returns a String or `nil`.
    def readme
      readme = repository.preferred_readme
      return if readme.nil? || readme.image?

      content = GitHub::HTML::MarkupFilter.html_from_blob(readme)
      return if content.nil? || content.empty?

      content = Nokogiri::HTML::DocumentFragment.parse(content).text.squish

      return if content.nil? || content.length > 512.kilobytes

      content
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e.with_redacting!, "gh.repo.id": repository.id)
      nil
    end

    # Helper method that combines topics pulled from an external service (Munger) as well as
    # those stored in the database for this repository.
    #
    # Returns an Array of hashes with the topic names as Strings and their ranks/weights
    # as floats.
    def ranked_hashtags
      applied_names = Set.new(repository.topics.pluck(:name))
      suggested_names = []
      result = []

      (applied_names - suggested_names).each do |name|
        result << { applied: name, rank: 0.5 }
      end

      result
    end

    # Helper method that returns the number of issues marked
    # "help wanted" for this repository
    def help_wanted_issues_count
      repository.help_wanted_issues_count
    end

    # Helper method that returns the number of issues marked
    # "good first issue" for this repository
    def good_first_issue_issues_count
      repository.good_first_issue_issues_count
    end

    # Helper method that returns the license ID for this repository from the
    # Licenses table.
    #
    # Returns the License ID or `nil`
    def license_id
      return unless repository && repository.repository_license
      repository.repository_license.license_id
    end

    # Custom property values assigned to this repo on its organization,
    # in a serialized-pair format
    def custom_property_values
      return @custom_property_values if defined? @custom_property_values
      return unless repository.owner&.organization?

      property_values = repository.custom_properties_effective_values
      property_values = property_values.compact
      @custom_property_values = property_values.flat_map do |property_name, value|
        Array(value).map { |v| "#{property_name}:#{v.downcase}" }
      end
    end
  end
end
