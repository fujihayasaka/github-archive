# typed: true
# frozen_string_literal: true

class Stafftools::Spark::UserInfoComponent < ApplicationComponent
  sig { params(user: User).void }
  def initialize(user:)
    @user = user
  end

  private

  sig { returns(User) }
  attr_reader :user

  sig { returns(T.nilable(T::Boolean)) }
  def render?
    logged_in?
  end

  sig { returns(Copilot::User) }
  memoize def copilot_user
    T.unsafe(Copilot::User).new(user)
  end

  sig { returns(T::Boolean) }
  def has_spark_access?
    with_database_error_fallback(fallback: false) do
      # has_spark_access? checks if the user has the licensing/access to use Spark
      # based on their Copilot plan (CFE/CFB with proper org settings, or CFI access)
      copilot_user.has_spark_access?
    end
  end

  sig { returns(T::Boolean) }
  def spark_enabled?
    with_database_error_fallback(fallback: false) do
      # spark_enabled? checks if Spark is enabled for the user
      # This already includes the has_spark_access? check plus configuration settings
      copilot_user.spark_enabled?
    end
  end

  sig { returns(String) }
  def access_status
    if spark_enabled?
      "Enabled"
    elsif has_spark_access?
      "Has access but disabled by configuration"
    else
      "No access"
    end
  end

  sig { returns(Integer) }
  memoize def total_spark_workbenches
    with_database_error_fallback(fallback: 0) do
      Spark::Workbench.where(user: user).count
    end
  end
end
