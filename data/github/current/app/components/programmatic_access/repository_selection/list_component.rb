# typed: strict
# frozen_string_literal: true

class ProgrammaticAccess::RepositorySelection::ListComponent < ApplicationComponent
  extend T::Sig

  ALL_PREFIX             = "personal_access_tokens.repository_selection.all"
  NONE_ACCESSIBLE_PREFIX = "personal_access_tokens.repository_selection.subset.none_accessible"
  NONE_PREFIX            = "personal_access_tokens.repository_selection.none"

  ACCOUNT      = "account"
  ENTERPRISE   = "enterprise"
  ORGANIZATION = "organization"

  sig { returns(T.untyped) }
  attr_reader :grantable

  sig { params(grantable: T.untyped, controller: String, action: String, page: Integer, repositories_path: String).void }
  def initialize(grantable, controller:, action:, page:, repositories_path:)
    @grantable = grantable
    @controller = controller
    @action = action
    @page = page
    @repositories_path = repositories_path

    @accessible_repositories_query = T.let(nil, T.untyped)
    @actor                         = T.let((requesting_access? ? @grantable.actor : @grantable.user_programmatic_access.owner), User)
    @repository_selection          = T.let(@grantable.repository_selection, String)
  end

  sig { returns(ActiveRecord::Relation) }
  def accessible_repositories
    accessible_repositories_query.order(:name).paginate(page: @page)
  end

  sig { returns(T::Boolean) }
  def accessible_repositories_exists?
    accessible_repositories_query.exists?
  end

  sig { returns(T::Boolean) }
  def target_adminable?
    target.adminable_by?(@actor)
  end

  sig { returns(String) }
  def heading_content
    key =
      case @repository_selection.to_sym
      when ProgrammaticAccessGrant::RepositorySelection::ALL
        suffix = if requesting_access?
          "requesting"
        elsif target_adminable?
          "granted.admin"
        else
          "granted.member"
        end

        "#{ALL_PREFIX}.#{suffix}"
      when ProgrammaticAccessGrant::RepositorySelection::SUBSET
        return "" unless accessible_repositories_query.none?
        suffix = requesting_access? ? "requesting" : "granted"

        "#{NONE_ACCESSIBLE_PREFIX}.#{suffix}"
      else
        suffix = requesting_access? ? "requesting" : "granted"
        "#{NONE_PREFIX}.#{suffix}"
      end

    t(key, actor: @actor.display_login, resource_owner_type: resource_owner_type)
  end

  private

  sig { returns(ActiveRecord::Relation) }
  def accessible_repositories_query
    return @accessible_repositories_query unless @accessible_repositories_query.nil?

    @accessible_repositories_query = if @grantable.is_a?(NullProgrammaticAccessGrant)
      Repository.none
    elsif target_adminable?
      @grantable.repositories
    end

    return @accessible_repositories_query unless @accessible_repositories_query.nil?

    options = { resource: "metadata" }

    if target.try(:organization?)
      options[:organization] = target
    end

    grantable_repository_ids = @grantable.repository_ids

    @accessible_repositories_query = Repositories::Public.accessible_repositories(
      repository_ids: grantable_repository_ids,
      associated_repository_ids: @actor.associated_repository_ids(
        repository_ids: grantable_repository_ids, **options
      )
    )
  end

  sig { returns(String) }
  def resource_owner_type
    case @grantable.target
    when Business
      ENTERPRISE
    when Organization
      ORGANIZATION
    else
      ACCOUNT
    end
  end

  sig { returns(T::Boolean) }
  def requesting_access?
    ProgrammaticAccessGrantRequest.is_request?(@grantable)
  end

  sig { returns(T.untyped) }
  def target
    @grantable.target
  end
end
