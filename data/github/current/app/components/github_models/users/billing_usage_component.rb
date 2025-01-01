# typed: true
# frozen_string_literal: true


class GitHubModels::Users::BillingUsageComponent < ApplicationComponent
  sig { params(user: User).void }
  def initialize(user:)
    @user = user
  end

  private

  sig { returns T.nilable(User) }
  attr_reader :user

  def billing_enablement_path
    models_user_billing_enablement_path(current_user)
  end

  def delete_billing_enablement_path
    delete_models_user_billing_enablement_path(current_user)
  end

  sig { returns(String) }
  def show_billing_text
    billing_enabled? ? "Enabled" : "Disabled"
  end

  sig { returns(T::Boolean) }
  def billing_enabled?
    @user.models_billing_enabled?
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.models_enabled?

    user_or_global_feature_enabled?(:github_models_billing_ui)
  end
end
