# typed: strict
# frozen_string_literal: true

module Growth
  class NoticeDismissal
    extend T::Sig

    USER_NOTICES = T.let([
      "test_notice_name"
    ], T::Array[String])

    ORGANIZATION_NOTICES = T.let(%w[
      test_notice_name
      upgrade-ghec-org-to-enterprise-account-dialog-notice
    ], T::Array[String])

    REPOSITORY_NOTICES = T.let([
      "test_notice_name"
    ], T::Array[String])

    BUSINESS_NOTICES = T.let(%w[
      test_notice_name
      sales_serve_enterprise_contract_expiration
    ], T::Array[String])

    sig { returns(::User) }
    attr_reader :user

    sig { params(user: User).void }
    def initialize(user)
      @user = user
    end

    sig { params(notice: String, repository_id: Integer, per_user: T::Boolean).returns(T::nilable(Time)) }
    def dismissed_repository_notice_at(notice, repository_id:, per_user: true)
      raise_unless_allowed_notice(notice, REPOSITORY_NOTICES)

      user_id = per_user ? user.id : nil
      value = get_notice("user.dismissed_repository_notice.#{notice}.#{repository_id}.#{user_id}")
      parse_dismissed_at_value(value)
    end

    sig { params(notice: String, org_id: Integer, per_user: T::Boolean).returns(T::nilable(Time)) }
    def dismissed_organization_notice_at(notice, org_id, per_user: true)
      raise_unless_allowed_notice(notice, ORGANIZATION_NOTICES)

      user_id = per_user ? user.id : nil
      value = get_notice("user.dismissed_organization_notice.#{notice}.#{org_id}.#{user_id}")
      parse_dismissed_at_value(value)
    end

    sig { params(notice: String, business_id: Integer, per_user: T::Boolean).returns(T::nilable(Time)) }
    def dismissed_business_notice_at(notice, business_id:, per_user: true)
      raise_unless_allowed_notice(notice, BUSINESS_NOTICES)

      user_id = per_user ? user.id : nil
      value = get_notice("user.dismissed_business_notice.#{notice}.#{business_id}.#{user_id}")
      parse_dismissed_at_value(value)
    end

    sig { params(notice: String).returns(T::nilable(Time)) }
    def dismissed_user_notice_at(notice)
      raise_unless_allowed_notice(notice, USER_NOTICES)

      value = get_notice("user.dismissed_notice.#{notice}.#{user.id}")
      parse_dismissed_at_value(value)
    end

    sig { params(notice: String, business_id: Integer, per_user: T::Boolean).returns(T::Boolean) }
    def dismissed_business_notice?(notice, business_id:, per_user: true)
      raise_unless_allowed_notice(notice, BUSINESS_NOTICES)

      user_id = per_user ? user.id : nil
      dismissed_notice?("user.dismissed_business_notice.#{notice}.#{business_id}.#{user_id}")
    end

    sig { params(notice: String, business_id: Integer, per_user: T::Boolean, expires: T.nilable(Time)).void }
    def dismiss_business_notice(notice, business_id:, per_user: true, expires: nil)
      raise_unless_allowed_notice(notice, BUSINESS_NOTICES)

      user_id = per_user ? user.id : nil
      dismiss_notice("user.dismissed_business_notice.#{notice}.#{business_id}.#{user_id}", expires: expires)
    end

    sig { params(notice: String, organization_id: Integer, per_user: T::Boolean, expires: T.nilable(Time)).void }
    def dismiss_organization_notice(notice, organization_id:, per_user: true, expires: nil)
      raise_unless_allowed_notice(notice, ORGANIZATION_NOTICES)

      if !dismissed_organization_notice?(notice, organization_id: organization_id, per_user: per_user)
        user_id = per_user ? user.id : nil
        dismiss_notice("user.dismissed_organization_notice.#{notice}.#{organization_id}.#{user_id}", expires: expires)
      end
    end

    sig { params(notice: String, organization_id: Integer, per_user: T::Boolean).returns(T::Boolean) }
    def dismissed_organization_notice?(notice, organization_id:, per_user: true)
      raise_unless_allowed_notice(notice, ORGANIZATION_NOTICES)

      user_id = per_user ? user.id : nil
      dismissed_notice?("user.dismissed_organization_notice.#{notice}.#{organization_id}.#{user_id}")
    end

    sig { params(notice: String, repository_id: Integer, per_user: T::Boolean, expires: T.nilable(Time)).void }
    def dismiss_repository_notice(notice, repository_id:, per_user: true, expires: nil)
      raise_unless_allowed_notice(notice, REPOSITORY_NOTICES)

      user_id = per_user ? user.id : nil
      dismiss_notice("user.dismissed_repository_notice.#{notice}.#{repository_id}.#{user_id}", expires: expires)
    end

    sig { params(notice: String, repository_id: Integer, per_user: T::Boolean).returns(T::Boolean) }
    def dismissed_repository_notice?(notice, repository_id:, per_user: true)
      raise_unless_allowed_notice(notice, REPOSITORY_NOTICES)

      user_id = per_user ? user.id : nil
      dismissed_notice?("user.dismissed_repository_notice.#{notice}.#{repository_id}.#{user_id}")
    end

    sig { params(notice: String, expires: T.nilable(Time)).void }
    def dismiss_user_notice(notice, expires: nil)
      raise_unless_allowed_notice(notice, USER_NOTICES)

      dismiss_notice("user.dismissed_notice.#{notice}.#{user.id}", expires: expires)
    end

    sig { params(notice: String).returns(T::Boolean) }
    def dismissed_user_notice?(notice)
      raise_unless_allowed_notice(notice, USER_NOTICES)

      dismissed_notice?("user.dismissed_notice.#{notice}.#{user.id}")
    end

    sig { params(notice: String).void }
    def reset_user_notice(notice)
      raise_unless_allowed_notice(notice, USER_NOTICES)

      delete_notice("user.dismissed_notice.#{notice}.#{user.id}")
    end

    sig { params(notice: String, business_id: Integer, per_user: T::Boolean).void }
    def reset_business_notice(notice, business_id:, per_user: true)
      raise_unless_allowed_notice(notice, BUSINESS_NOTICES)

      user_id = per_user ? user.id : nil
      delete_notice("user.dismissed_business_notice.#{notice}.#{business_id}.#{user_id}")
    end

    sig { params(notice: String, organization_id: Integer, per_user: T::Boolean).void }
    def reset_organization_notice(notice, organization_id:, per_user: true)
      raise_unless_allowed_notice(notice, ORGANIZATION_NOTICES)

      user_id = per_user ? user.id : nil
      delete_notice("user.dismissed_organization_notice.#{notice}.#{organization_id}.#{user_id}")
    end

    sig { params(notice: String, repository_id: Integer, per_user: T::Boolean).void }
    def reset_repository_notice(notice, repository_id:, per_user: true)
      raise_unless_allowed_notice(notice, REPOSITORY_NOTICES)

      user_id = per_user ? user.id : nil
      delete_notice("user.dismissed_repository_notice.#{notice}.#{repository_id}.#{user_id}")
    end

    private

    sig { params(key: String).returns(T::Boolean) }
    def dismissed_notice?(key)
      ActiveRecord::Base.connected_to(role: :reading) do
        Growth::KV.store.get(key).value { true }.present?
      end
    end

    sig { params(key: String, expires: T.nilable(Time)).void }
    def dismiss_notice(key, expires: nil)
      options = expires ? { expires: expires } : {}
      ActiveRecord::Base.connected_to(role: :writing) do
        Growth::KV.store.set(key, Time.now.utc.iso8601, **options)
      end
    end

    sig { params(value: T::nilable(String)).returns(T::nilable(Time)) }
    def parse_dismissed_at_value(value)
      return if value.nil?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end

    sig { params(key: String).void }
    def delete_notice(key)
      ActiveRecord::Base.connected_to(role: :writing) do
        Growth::KV.store.del(key)
      end
    end

    sig { params(key: String).returns(T::nilable(String)) }
    def get_notice(key)
      ActiveRecord::Base.connected_to(role: :reading) do
        Growth::KV.store.get(key).value!
      end
    end

    sig { params(notice: String, notice_list: T::Array[String]).void }
    def raise_unless_allowed_notice(notice, notice_list)
      raise ArgumentError, "Invalid notice: #{notice}" unless notice_list.include?(notice)
    end
  end
end
