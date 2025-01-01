# typed: strict
# frozen_string_literal: true

module App

  # This interface represents the execution context for presentation and app tier request processing. On web
  # and REST, the data for this interface is typically gleaned from the request object's url or parameters.
  class SimpleContext
    extend T::Sig
    extend T::Helpers

    include IContext

    sig { void }
    def initialize
      @repository = T.let(nil, T.nilable(Repositories::IRepository))
      @user = T.let(nil, T.nilable(Users::IUser))
      @organization = T.let(nil, T.nilable(Orgs::IOrganization))
      @business = T.let(nil, T.nilable(Admin::IBusiness))
      @actor = T.let(nil, T.nilable(Users::IUser))
      @request_credentials = T.let(nil, T.nilable(App::IRequestCredentials))
    end

    sig { override.returns(T.nilable(Repositories::IRepository)) }
    attr_reader :repository

    sig { override.returns(T.nilable(Users::IUser)) }
    attr_reader :user

    sig { override.returns(T.nilable(T.any(Orgs::IOrganization, Business))) }
    attr_reader :organization

    sig { override.returns(T.nilable(Admin::IBusiness)) }
    attr_reader :business

    sig { override.returns(T.nilable(Users::IUser)) }
    attr_reader :actor

    sig { override.returns(App::IRequestCredentials) }
    def request_credentials
      raise NotImplementedError
    end

    sig { params(repository: T.nilable(Repositories::IRepository)).returns(T.nilable(Repositories::IRepository)) }
    attr_writer :repository

    sig { params(user: T.nilable(Users::IUser)).returns(T.nilable(Users::IUser)) }
    attr_writer :user

    sig { params(organization: T.nilable(Orgs::IOrganization)).returns(T.nilable(Orgs::IOrganization)) }
    attr_writer :organization

    sig { params(business: T.nilable(Admin::IBusiness)).returns(T.nilable(Admin::IBusiness)) }
    attr_writer :business

    sig { params(actor: T.nilable(Users::IUser)).returns(T.nilable(Users::IUser)) }
    attr_writer :actor

    sig { params(request_credentials: App::IRequestCredentials).void }
    attr_writer :request_credentials
  end
end
