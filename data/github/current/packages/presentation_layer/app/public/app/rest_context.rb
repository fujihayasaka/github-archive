# typed: strict
# frozen_string_literal: true

module App
  class RestContext < SimpleContext
    extend T::Sig
    extend T::Helpers

    include Users::Domain::Provider
    include IContext

    sig { params(app: IController).void }
    def initialize(app:)
      @app = T.let(app, IController)
      super()

      @repository = T.let(nil, T.any(NilClass, Repositories::IRepository, GH::Result::Error::NotFound[Repositories::IRepository]))
      @user = T.let(nil, T.any(NilClass, Users::IUser, GH::Result::Error::NotFound[Users::IUser]))
      @organization = T.let(nil, T.any(NilClass, Orgs::IOrganization, Business, GH::Result::Error::NotFound[Orgs::IOrganization]))
      @business = T.let(nil, T.any(NilClass, Admin::IBusiness, GH::Result::Error::NotFound[Admin::IBusiness]))

      @actor = T.let(nil, T.any(NilClass, Users::IUser, GH::Result::Error::NotFound[Repositories::IRepository]))
      @request_credentials = T.let(nil, T.nilable(IRequestCredentials))
    end

    sig { override.returns(T.nilable(Repositories::IRepository)) }
    def repository
      @repository = find_repo if !@repository

      return nil if @repository.is_a?(GH::Result::Error::NotFound)
      @repository
    end

    sig { override.returns(T.nilable(Users::IUser)) }
    def user
      @user = find_user if !@user

      return nil if @user.is_a?(GH::Result::Error::NotFound)
      @user
    end

    sig { override.returns(T.nilable(T.any(Orgs::IOrganization, Business))) }
    def organization
      @organization = find_org if !@organization

      return nil if @organization.is_a?(GH::Result::Error::NotFound)
      @organization
    end

    sig { override.returns(T.nilable(Admin::IBusiness)) }
    def business
      @business = find_business if !@business

      return nil if @business.is_a?(GH::Result::Error::NotFound)
      @business
    end

    sig { override.returns(T.nilable(Users::IUser)) }
    def actor
      @actor = app.current_user if @actor.nil?
      @actor = GH::Result::Error::NotFound.new if @actor.nil?

      return nil if @actor.is_a?(GH::Result::Error::NotFound)

      @actor
    end

    sig { override.returns(IRequestCredentials) }
    def request_credentials
      @request_credentials ||= Api::RequestCredentials.from_env(app.env)
    end

    sig { returns(T.nilable(T.any(Substrate::IRepositoryOwner, Admin::IBusiness))) }
    def resource_org_or_biz_owner
      # This relies on checking ivars because that is what historical code did in finders_dependency.
      # In the interest of not changing too many things at once, this behaviour will remain, even if
      # it doesn't make a lot of sense.
      # TODO: Stop relying on caching ivars to dictate logic.
      return @organization if @organization.is_a?(Substrate::IRepositoryOwner)
      @business if @business.is_a?(Admin::IBusiness)
    end

    private

    sig { returns(IController) }
    attr_reader :app

    # Internal: Selects the Repository defined in the URL of all Repository paths:
    #  /repositories/:repository_id
    sig { returns(T.any(NilClass, Repositories::IRepository, GH::Result::Error::NotFound[Repositories::IRepository])) }
    def find_repo
      repo = app.env[GitHub::Routers::Api::ThisRepositoryKey]
      return repo if repo

      id_param = app.params[:repository_id]&.b
      id = T.let(id_param.to_i, Integer)

      if id <= 0
        # We had a value but it didn't parse as an integer. This isn't going to get better so let's just cache
        # the result as not found and not try again.
        return GH::Result::Error::NotFound.new unless id_param.blank?

        # We may simply tried to load the repo before the id param has had a chance to be set. Don't cache this.
        return nil
      end

      repo = Repositories::Public.find_active(id)
      return repo unless repo.nil?

      GH::Result::Error::NotFound.new
    end

    # Internal: Finds the user identified by the URL. This is loaded separately from the current repository
    # because the url might resolve to a target user but not a repository.
    sig { returns(T.any(Users::IUser, GH::Result::Error::NotFound[Users::IUser])) }
    def find_user
      user = app.env[GitHub::Routers::Api::ThisUserKey]
      return user if user

      id = app.params[:user_id].to_i

      users_domain.by_id(id) || GH::Result::Error::NotFound.new
    end

    # Internal: Finds the org - or business (?) - identified by the owner portion of the URL. This is loaded
    # separately from the current repository because the url might resolve to an org but not a repository.
    sig { returns(T.any(Orgs::IOrganization, Business, GH::Result::Error::NotFound[Orgs::IOrganization])) }
    def find_org
      org = app.env[GitHub::Routers::Api::ThisUserKey]
      return org if org&.is_a?(Orgs::IOrganization) && org&.active?

      id = app.params[:organization_id].to_i
      name = app.params[:org].to_s
      accessor = Orgs::OrganizationAccessor.new

      accessor.by_id(id) ||
        accessor.by_name(name) ||
        GH::Result::Error::NotFound.new
    end

    sig { returns(T.any(Admin::IBusiness, GH::Result::Error::NotFound[Admin::IBusiness])) }
    def find_business
      Business.find_by(id: app.params[:enterprise_id]) ||
        Business.find_by(slug: app.params[:enterprise_id]) ||
        GH::Result::Error::NotFound.new
    end
  end
end
