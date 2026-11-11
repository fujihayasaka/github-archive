# typed: strict
# frozen_string_literal: true

# Diagnostic tool for comparing dotcom's Code Quality repository enablements and
# active committer licensee IDs to Licensify for a single customer. Not used in
# application code paths.
#
# Usage (from console):
#
#   biz = Business.find_by_slug("some-customer")
#   v = CodeQuality::LicensifyValidator.new(biz)
#
#   org = Organization.find_by_login("some-org")
#   v = CodeQuality::LicensifyValidator.new(org)
#
#   v.to_h          # => summary with counts, match status, warnings
#   v.match?        # => true/false
#   v.repo_diff      # => detailed repository-level diff
#   v.licensee_diff  # => detailed licensee-level diff
#   v.counts         # => counts of enabled repositories/licensees in dotcom and Licensify
#
class CodeQuality::LicensifyValidator
  extend T::Helpers
  include Licensing::Licensify
  include GitHub::Memoizer

  Owner = T.type_alias { T.any(Business, Organization) }

  sig { params(owner: Owner).void }
  def initialize(owner)
    @owner = owner
  end

  sig { returns(T.nilable(Integer)) }
  memoize def customer_id
    Licensing::Customer.id_for(@owner)
  end

  sig { returns(T::Hash[Symbol, T::Hash[Symbol, Integer]]) }
  memoize def counts
    {
      enabled_repositories: {
        dotcom: dotcom_repository_ids.size,
        licensify: licensify_repository_ids.size,
      },
      licensees: {
        dotcom: dotcom_licensee_ids.size,
        licensify: licensify_licensee_ids.size,
      },
    }
  end

  sig { returns(T::Boolean) }
  def match?
    dotcom_repository_ids == licensify_repository_ids &&
      dotcom_licensee_ids == licensify_licensee_ids
  end

  sig { returns(T::Array[String]) }
  memoize def warnings
    result = T.let([], T::Array[String])

    if customer_id.nil?
      result << "No Licensify customer linked to this owner. Licensify repository enablements and licensee IDs will be 0."
    end

    result
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def repo_diff
    dotcom_ids = dotcom_repository_ids
    licensify_ids = licensify_repository_ids

    only_in_dotcom = dotcom_ids - licensify_ids
    only_in_licensify = licensify_ids - dotcom_ids
    common_ids = dotcom_ids & licensify_ids

    {
      dotcom_count: dotcom_ids.size,
      licensify_count: licensify_ids.size,
      in_common: common_ids.size,
      only_dotcom: resolve_repositories(only_in_dotcom),
      only_licensify: resolve_repositories(only_in_licensify, include_missing: true),
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def licensee_diff
    dotcom_ids = dotcom_licensee_ids
    licensify_ids = licensify_licensee_ids

    only_in_dotcom = dotcom_ids - licensify_ids
    only_in_licensify = licensify_ids - dotcom_ids
    common_ids = dotcom_ids & licensify_ids

    {
      dotcom_count: dotcom_ids.size,
      licensify_count: licensify_ids.size,
      in_common: common_ids.size,
      only_dotcom: resolve_users(only_in_dotcom),
      only_licensify: resolve_users(only_in_licensify, include_missing: true),
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_h
    {
      customer_id: customer_id,
      owner_id: @owner.id,
      owner_type: @owner.class.name,
      owner_name: owner_name,
      counts: counts,
      match: match?,
      warnings: warnings,
    }
  end

  private

  sig { returns(String) }
  def owner_name
    case @owner
    when Business then @owner.slug
    when Organization then @owner.display_login
    else T.absurd(@owner)
    end
  end

  sig { returns(T::Array[Integer]) }
  def organization_ids
    case @owner
    when Business then @owner.organization_ids
    when Organization then [@owner.id]
    else T.absurd(@owner)
    end
  end

  sig { returns(ActiveRecord::Relation) }
  def repository_scope
    Repository.active
      .private_scope
      .where(owner_id: organization_ids)
      .where(archived_at: nil)
  end

  sig { returns(T::Set[Integer]) }
  memoize def dotcom_repository_ids
    enabled_ids = T.let(Set.new, T::Set[Integer])

    repository_scope.in_batches(of: 1_000) do |relation|
      repos = relation.to_a
      preload_repository_dependencies(repos)

      repos.each do |repo|
        next unless CodeQualityEnablement.new(repo).enabled?

        enabled_ids.add(repo.id)
      end
    end

    enabled_ids
  end

  sig { returns(T::Set[Integer]) }
  memoize def licensify_repository_ids
    return Set[] if customer_id.nil?

    get_all_product_enablement_ids(
      T.must(customer_id),
      product: Licensing::Licensify::LicensifyProduct::CODE_QUALITY,
      enablement_type: ::Licensify::Services::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO,
    ).to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def dotcom_licensee_ids
    dotcom_committers
      .filter_map { |committer| non_zero_integer(committer.id) }
      .to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def licensify_licensee_ids
    return Set[] if customer_id.nil?

    get_licensify_licensee_ids(
      T.must(customer_id),
      product: Licensing::Licensify::LicensifyProduct::CODE_QUALITY,
      enablement_reasons: [
        ::Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COMMITTER,
      ],
    ).filter_map { |licensee_id| non_zero_integer(licensee_id) }.to_set
  end

  sig { returns(T::Array[::Turboghas::Proto::GetCommittersResponse::Committer]) }
  memoize def dotcom_committers
    repository_ids = dotcom_repository_ids.to_a
    return [] if repository_ids.empty?

    committers = T.let([], T::Array[::Turboghas::Proto::GetCommittersResponse::Committer])
    cursor = T.let(nil, T.untyped)

    loop do
      response = Business::AdvancedSecurityCommittersGenerator.get_committers_paginated(
        @owner,
        limit: Business::AdvancedSecurityCommittersGenerator::GET_COMMITTERS_MAX_PAGE_SIZE,
        cursor: cursor,
        # Code Quality does not have a TurboGHAS feature/SKU. The repository_ids
        # filter has already scoped this to Code Quality-enabled repositories, so
        # avoid ACTIVE_COMMITTERS' TurboGHAS product-feature filter.
        committer_type: :MAXIMUM_COMMITTERS,
        repository_ids: repository_ids,
        sku: GitHub::Turboghas::SKU::Bundled,
      )

      committers.concat(response.committers.to_a)
      cursor = response.next_cursor
      break if cursor.blank?
    end

    committers
  end

  sig { params(repositories: T::Array[Repository]).void }
  def preload_repository_dependencies(repositories)
    Configurable.preload_configuration(repositories)
    SecurityProductsEnablement::RepositorySecuritySettings.preload_settings_for(repositories)
  end

  sig { params(repository_ids: T::Set[Integer], include_missing: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def resolve_repositories(repository_ids, include_missing: false)
    return [] if repository_ids.empty?

    repositories_by_id = Repository.where(id: repository_ids.to_a).index_by(&:id)

    repository_ids.filter_map do |repository_id|
      repository = repositories_by_id[repository_id]
      if repository
        {
          id: repository.id,
          name_with_owner: repository.name_with_display_owner,
          active: repository.active?,
          archived: repository.archived?,
        }
      elsif include_missing
        {
          id: repository_id,
          name_with_owner: "(unknown)",
          missing: true,
        }
      end
    end
  end

  sig { params(user_ids: T::Set[Integer], include_missing: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def resolve_users(user_ids, include_missing: false)
    return [] if user_ids.empty?

    users_by_id = User.where(id: user_ids.to_a).index_by(&:id)

    user_ids.filter_map do |user_id|
      user = users_by_id[user_id]
      if user
        {
          id: user.id,
          login: user.display_login,
        }
      elsif include_missing
        {
          id: user_id,
          login: "(unknown)",
          missing: true,
        }
      end
    end
  end

  sig { params(value: T.untyped).returns(T.nilable(Integer)) }
  def non_zero_integer(value)
    return nil unless value.to_s.match?(/\A\d+\z/)

    integer = value.to_i
    return nil if integer.zero?

    integer
  end

  sig { returns(T::Hash[String, String]) }
  def licensify_error_tags
    {
      "gh.billing.customer.id": customer_id,
      "gh.billable_entity.id": @owner.id,
      "gh.billable_entity.type": @owner.class.name,
      "licensify.product": Licensing::Licensify::LicensifyProduct::CODE_QUALITY.to_s,
    }
  end
end
