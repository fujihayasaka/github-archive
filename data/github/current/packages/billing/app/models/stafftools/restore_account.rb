# typed: strict
# frozen_string_literal: true

class Stafftools::RestoreAccount
  # Public: Restore an account using the details provided. This attempts to save
  # the account after it's been restored. Users will be restored with a random
  # password and Organizations will be restored with a single admin, the
  # current user.
  #
  # current_user - The user performing the restore
  # details      - A hash of account details
  #   :id      - String or Integer id of account
  #   :login   - String login for account
  #   :email   - String email for account
  #   :plan    - String plan name for account
  #   :was_org - String boolean "true" if this account was an Organization
  #
  # Returns the restored account. This will be a User or Organization.
  sig { params(current_user: ::User, details: T::Hash[Symbol, String]).returns(T.any(::User, ::Organization)) }
  def self.perform(current_user, details)
    new(current_user, details).perform
  end

  sig { params(current_user: ::User, details: T::Hash[Symbol, String]).void }
  def initialize(current_user, details)
    @current_user = current_user
    @id = T.let(details.fetch(:id).to_i, Integer)
    @login = T.let(details.fetch(:login), String)
    @email = T.let(details.fetch(:email), String)
    @plan = T.let(details.fetch(:plan), String)
    @was_org = T.let((details.fetch(:was_org) == "true"), T::Boolean)
  end

  sig { returns(T.any(::User, ::Organization)) }
  def perform
    was_org ? restore_org : restore_user
  end

  private

  sig { returns(::User) }
  attr_reader :current_user
  sig { returns(Integer) }
  attr_reader :id
  sig { returns(String) }
  attr_reader :login
  sig { returns(String) }
  attr_reader :email
  sig { returns(String) }
  attr_reader :plan
  sig { returns(T::Boolean) }
  attr_reader :was_org

  sig { returns(::User) }
  def restore_user
    password = SecureRandom.hex(32)

    ReservedLogin.untombstone!(login)

    user = User.new \
      login: login,
      email: email,
      plan: plan,
      password: password,
      password_confirmation: password
    user.id = id

    if user.save
      GitHub.instrument "user.recreate", { user: user }
    end

    begin
      # rollback untombstone if user is not persisted
      # this used to be a nested deeply transaction, but was purposefully removed
      ReservedLogin.tombstone!(login) if !user.persisted?
    rescue ActiveRecord::RecordInvalid => ex
      # noop when login is invalid
    end

    user
  end

  sig { returns(::Organization) }
  def restore_org
    if org = soft_deleted_org(login)
      org.mark_not_deleted(actor: current_user)
      return org
    end

    ReservedLogin.untombstone!(login)

    org = Organization.new \
      login: login,
      plan: plan,
      billing_email: email.blank? ? "billing@example.com" : email,
      admins: [current_user],
      company_name: login
    org.id = id

    if org.save
      if GitHub.single_business_environment? && GitHub.global_business
        # Ensure the org is added to the global enterprise account.
        GitHub.global_business.add_organization org
      end

      GitHub.instrument "org.recreate", { org: org }
    end

    begin
      # rollback untombstone if org is not persisted
      # this used to be a nested deeply transaction, but was purposefully removed
      ReservedLogin.tombstone!(login) if !org.persisted?
    rescue ActiveRecord::RecordInvalid => ex
      # noop when login is invalid
    end

    org
  end

  sig { params(login: String).returns(T.nilable(::Organization)) }
  def soft_deleted_org(login)
    org = Organization.find_by(login: login)
    org&.soft_deleted? ? org : nil
  end
end
