# typed: strict
# frozen_string_literal: true

module Billing::RepositoryVisibility
  extend ActiveSupport::Concern

  extend T::Helpers

  sig { params(repo: T.nilable(Repository)).returns(Integer) }
  def billing_repo_visibility(repo)
    if repo.nil?
      GitHub.logger.info(
        "billing_repo_visibility: Unexpected nil repository"
      )
      return BillingPlatform::Base::RepositoryVisibility::VISIBILITY_UNKNOWN
    end

    case repo.visibility.to_sym
    when :public
      BillingPlatform::Base::RepositoryVisibility::PUBLIC
    when :private
      BillingPlatform::Base::RepositoryVisibility::PRIVATE
    when :internal
      BillingPlatform::Base::RepositoryVisibility::INTERNAL
    else
      GitHub.logger.info(
        "billing_repo_visibility: Unexpected unknown repository visibility",
        "gh.repo.visibility" => repo.visibility.to_sym,
        "gh.repo.id" => repo.id,
      )
      BillingPlatform::Base::RepositoryVisibility::VISIBILITY_UNKNOWN
    end
  end
end
