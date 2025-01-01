# typed: true
# frozen_string_literal: true

module Business::RepositoryDependency
  include BusinessesHelper
  include GitHub::Memoizer

  extend ActiveSupport::Concern
  extend T::Helpers

  VALID_DIRECTION_FIELDS = %w(asc desc).freeze

  requires_ancestor { Business }

  # Public: Does this business allow for user repositories to be viewed?
  def show_user_namespace_repositories?
    enterprise_managed_user_enabled?
  end

  # Public: Does this business allow for user repositories to be unlocked?
  def allow_unlock_user_namespace_repositories?
    show_user_namespace_repositories?
  end

  # Public: Can the given user unlock user-owned repositories?
  def can_user_unlock_user_namespace_repos?(user)
    return false unless GitHub.enterprise? || allow_unlock_user_namespace_repositories?

    T.bind(self, Business)

    # Business owners can always unlock repositories, but we also allow folks like enterprise security managers
    # to unlock user-owned repositories so they can manage code security alerts from them.
    biz_auth = ::SecurityProduct::Permissions::BusinessAuthz.new(self, actor: user)
    return true if biz_auth.can_view_user_owned_repository_alerts?

    # 'can_view_user_owned_repository_alerts?' used above returns true for business owners, but
    # this method isn't related to code security alerts, so we'll keep the explicit check for owner.
    self.owner?(user)
  end

  # Public: Returns user namespace repositories of the enterprise.
  #
  # optional arguments:
  # query               - The user-provided query string
  # status              - Filter by repository status. Supported: :active, :deleted, :unlocked. Default: :active.
  # repository_ids      - Array of repository ids to filter by. Default: all repositories.
  # sort_direction      - String specifying the sort direction. Supported: "asc", "desc". Default: "asc".
  # sort_field          - String specifying the sort field. Supported: "updated", "owner". Default: "updated".
  #
  # Returns an ActiveRecord::Relation
  def user_namespace_repositories(
    query: nil,
    status: :active,
    repository_ids: [],
    sort_direction: nil,
    sort_field: nil
  )
    return unless enterprise_managed_user_enabled?

    filtered_repository_ids = self.write_through_cache.get_and_update(:user_namespace_repositories_ids)
    filtered_repository_ids = filtered_repository_ids & repository_ids if repository_ids.present?

    scope = Repository.where(id: filtered_repository_ids)
    scope = apply_query_filter(scope, query)

    case status
    when :deleted
      scope = scope.network_safe_restoreable
      sort_field = selected_sort_field("updated") if sort_field.nil?
      sort_direction = "desc" if sort_direction.nil?
    when :unlocked
      # Repository_ids should be supplied when looking for unlocked repositories
      return Repository.none unless repository_ids.present?
      # Ignore deleted unlocked repositories, as they cannot be accessed by the actor unlocking them
      scope = scope.active
    else
      scope = scope.active
    end

    sort_field = selected_sort_field(sort_field)
    sort_direction = "asc" unless VALID_DIRECTION_FIELDS.include?(sort_direction.to_s.downcase)

    scope.order("#{sort_field} #{sort_direction}")
  end

  def user_namespace_repositories_ids
    return unless enterprise_managed_user_enabled?

    Repository.batched_scope(:owner_id, values: user_ids).pluck(:id)
  end

  def destroy_custom_properties
    CustomProperties::Public.destroy_all_definitions(T.bind(self, Business))
  end

  # Public: Get the Organizations that do or do not have deploy keys.
  #
  # has_deploy_keys - Required Boolean indicating whether to return those orgs
  #   that have (true) or does not have (false) deploy keys.
  # orgs - Optional ActiveRecord::Relation if this method should apply to an existing
  #   collection of Organizations. Defaults to Business#organizations.
  #
  # Returns an ActiveRecord Relation scoped to organizations that do or do not deploy keys
  def organizations_with_deploy_keys_filter(has_deploy_keys, orgs: organizations)
    return Organization.none if orgs.none?

    org_ids = orgs.pluck(:id)
    repository_ids_by_org_id = Repository.where(owner_id: org_ids).select(:id, :owner_id).group_by(&:owner_id)

    org_ids_with_deploy_keys = []
    repository_ids_by_org_id.each do |org_id, repository_ids|
      next if repository_ids.empty?
      deploy_key_ids = PublicKey.where(repository_id: repository_ids).pluck(:id)
      org_ids_with_deploy_keys << org_id if deploy_key_ids.any?
    end

    if has_deploy_keys
      orgs.where(id: org_ids_with_deploy_keys)
    else
      orgs.where.not(id: org_ids_with_deploy_keys)
    end
  end

  private

  # Initialize the deploy key policy for the business
  def initialize_deploy_key_policy
    # Many test cases rely on the deploy key policy being enabled by default
    # so we should not disable it in test environments.
    return if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    self.configure_deploy_key_policy_on_creation(actor: actor, enable: false)
  end

  def user_ids
    self.user_accounts.pluck(:user_id).compact
  end

  def apply_query_filter(scope, query)
    return scope if query.blank?

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    scope.where(["repositories.name LIKE :query OR repositories.owner_login LIKE :query", { query: "%#{query}%" }])
  end

  def selected_sort_field(field)
    case field
    when "updated"
      "repositories.pushed_at"
    when "owner"
      "repositories.owner_login"
    else
      "repositories.owner_login"
    end
  end
end
