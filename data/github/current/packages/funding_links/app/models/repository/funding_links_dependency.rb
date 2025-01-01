# typed: true
# frozen_string_literal: true

require_relative "../../../../github_sponsors/app/models/sponsors/k_v"

module Repository::FundingLinksDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include Configurable::RepositoryFundingLinks

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    batch_method :funding_links_stafftools_disabled? do |repos|
      keys_by_repo = repos.map { |repo| [repo, repo.funding_links_stafftools_kv_prefix] }.to_h
      repo_values = Sponsors::KV.store.mget(keys_by_repo.values).value { [] }
      repo_result_pairs = repos.map.with_index do |repo, index|
        result = ActiveRecord::Type::Boolean.new.cast(repo_values[index])
        [repo, result]
      end
      repo_result_pairs.to_h
    end

    # Public: Indicates if if the repository's funding file is inherited from the
    #         global repository.
    #
    # Returns a Boolean.
    batch_method :inheriting_global_funding_file? do |repos|
      promises = repos.map { |repo| repo.preferred_files.async_inherited?(:funding) }
      results = Promise.all(promises).sync
      repos.zip(results).to_h
    end

    batch_method :global_funding_file_repository_funding_links_enabled? do |repos|
      promises = repos.map do |repo|
        repo.async_global_health_files_repo.then do |global_repo|
          next false unless global_repo

          global_repo.async_repository_funding_links_explicitly_enabled?.then do |explicitly_enabled|
            next true if explicitly_enabled
            next false if global_repo.fork?

            global_repo.async_repository_funding_links_unset?.then do |is_unset|
              is_unset ? global_repo.async_has_funding_file? : false
            end
          end
        end
      end

      results = Promise.all(promises).sync
      repos.zip(results).to_h
    end

    batch_method :repository_funding_links_enabled? do |repos|
      promises = repos.map do |repo|
        business_promise = if GitHub.enterprise?
          repo.async_owner.then { |owner| owner.async_business }
        else
          Promise.resolve(nil)
        end
        repo.async_repository_funding_links_explicitly_enabled?.then do |explicitly_enabled|
          next true if explicitly_enabled

          repo.async_repository_funding_links_unset?.then do |is_unset|
            next false unless is_unset

            repo.async_has_funding_file?.then do |has_funding_file|
              next true if has_funding_file && !repo.fork?

              business_promise.then do
                Promise.all([
                  repo.async_batch_inheriting_global_funding_file?,
                  repo.async_batch_global_funding_file_repository_funding_links_enabled?,
                ]).then do |inheriting_global_funding_file, global_funding_links_enabled|
                  inheriting_global_funding_file && global_funding_links_enabled
                end
              end
            end
          end
        end
      end

      results = Promise.all(promises).sync
      repos.zip(results).to_h
    end
  end

  # Public: True if the User or Organization that owns the repository has enabled
  # the funding links and is in the feature flag.
  sig { returns T::Boolean }
  def can_enable_repository_funding_links?
    GitHub.sponsors_enabled? && !has_any_trade_restrictions?
  end

  # Public: True if the repository can use funding links and the user can write
  # a funding file
  sig { returns T::Boolean }
  def can_write_funding_file?
    return false unless can_enable_repository_funding_links?

    # Handle e.g. the case where .github is already a file that exists
    # so a new .github directory cannot be created
    valid_file_path?(funding_links_path)
  end

  # Public: Indicates if the repository has a funding file.
  sig { returns T::Boolean }
  def has_funding_file?
    async_has_funding_file?.sync
  end

  # Public: Does this repository have a funding links file?
  sig { returns Promise[T::Boolean] }
  def async_has_funding_file?
    preferred_files.async_exists?(:funding)
  end

  # Public: Indicates if the repository has a local funding file AND a global
  #         funding file.
  sig { returns T::Boolean }
  def overriding_global_funding_file?
    return false if global_health_files_repository? # we ARE the global funding repo
    return false unless global_funding = preferred_files.fetch(:funding, global: true)

    preferred_files.fetch(:funding) != global_funding
  end

  # Public: The path of the FUNDING.yml file (can be in the root, in a .github directory, or in a docs directory)
  #
  # Returns path to to the funding file for the repo if it exists. Otherwise, returns ".github/FUNDING.yml"
  sig { returns String }
  def funding_links_path
    path = preferred_file(:funding)&.path

    if path && !inheriting_global_funding_file?
      path
    else
      FundingLinks::PATH
    end
  end

  sig { returns FundingLinks }
  def funding_links
    @funding_links ||= FundingLinks.for(repository: T.cast(self, Repository)) # rubocop:todo GitHub/AvoidCast
  end

  sig { returns T::Array[T::Hash[Symbol, String]] }
  def funding_links_to_hydro
    @funding_links_to_hydro ||= begin
      funding_links.validated_config.each_with_object(Array.new) do |links, result|
        platform_key, value = links
        accounts = Array(value)

        if platform = FundingPlatforms.find(platform_key)
          accounts.each do |account|
            result << FundingPlatforms.to_hydro(platform, account)
          end
        end
      end.compact
    end
  end

  sig { returns T::Boolean }
  def has_funding_platforms?
    return false unless has_funding_file?

    funding_links.validated_config.any?
  end

  sig { returns String }
  def funding_links_stafftools_kv_prefix
    "stafftools_repository_funding_links_disabled_#{self.id}"
  end
end
