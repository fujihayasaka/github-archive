# typed: strict
# frozen_string_literal: true

module App
  # This interface represents the execution context for presentation and app tier request processing. On web
  # and REST, the data for this interface is typically gleaned from the request object's url or parameters.
  module IContext
    extend T::Helpers

    interface!

    # Public: The currently selected repository, if any.
    sig { abstract.returns(T.nilable(Repositories::IRepository)) }
    def repository; end

    # Public: The currently selected user, if any.
    sig { abstract.returns(T.nilable(Users::IUser)) }
    def user; end

    # Public: The currently selected organization, if any.
    # TODO: Get Business out of this signature. In some routes it is added to the env under the key
    # GitHub::Routers::Api::ThisUserKey. This should not happen.
    sig { abstract.returns(T.nilable(T.any(Orgs::IOrganization, Business))) }
    def organization; end

    # Public: The currently selected business, if any.
    sig { abstract.returns(T.nilable(Admin::IBusiness)) }
    def business; end

    # Public: The currently authenticated actor, or nil if it is an anonymous request.
    sig { abstract.returns(T.nilable(Users::IUser)) }
    def actor; end

    # Public: The request credentials for the current request.
    sig { abstract.returns(App::IRequestCredentials) }
    def request_credentials; end
  end
end
