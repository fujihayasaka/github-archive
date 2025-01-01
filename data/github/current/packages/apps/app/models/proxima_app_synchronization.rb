# typed: strict
# frozen_string_literal: true

class ProximaAppSynchronization < ApplicationRecord::Domain::Integrations

  belongs_to :local_app, polymorphic: true

  # defaults for create, find, and find_all

  # Public: Has the given app been synchronized from Dotcom? Only works within
  # a Proxima (multi-tenant) environment.
  #
  # Returns a Boolean.
  sig { params(app: Proxima::Syncable).returns(T::Boolean) }
  def self.synchronized?(app)
    return false unless GitHub.multi_tenant_enterprise?

    exists?(local_app: app)
  end

  # Public: Has the given app been synchronized from Dotcom and is it a
  # "first-party" app? Only works within a Proxima (multi-tenant) environment.
  #
  # Returns a Boolean.
  sig { params(app: Proxima::Syncable).returns(T::Boolean) }
  def self.synchronized_first_party?(app)
    synchronized?(app) && app.owner == GitHub.first_party_apps_owner
  end

  # Public: Has the given app been synchronized from Dotcom and is it a
  # "third-party" app? Only works within a Proxima (multi-tenant) environment.
  #
  # Returns a Boolean.
  sig { params(app: Proxima::Syncable).returns(T::Boolean) }
  def self.synchronized_third_party?(app)
    synchronized?(app) && app.owner == GitHub.proxima_third_party_apps_owner
  end

  # Internal: The URL of the app's canonical avatar, which is synchronized from
  # Dotcom to Proxima stamps in the case of first and third-party apps.
  #
  # Returns a String or nil.
  sig { params(app: Proxima::Syncable).returns(T.nilable(String)) }
  def self.canonical_avatar_url_for(app)
    return nil unless GitHub.multi_tenant_enterprise?

    find_by(local_app: app)&.canonical_avatar_url
  end

end
