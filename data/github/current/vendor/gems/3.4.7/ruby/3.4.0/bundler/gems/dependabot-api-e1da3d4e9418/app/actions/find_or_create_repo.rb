# frozen_string_literal: true

class FindOrCreateRepo
  attr_reader :github_repo

  def initialize(github_repo:)
    @github_repo = github_repo.to_h
  end

  def run
    account_github_id = github_repo.fetch(:owner).fetch(:id)
    type = translate_account_type(github_repo.fetch(:owner).fetch(:type))
    account =
      FindOrUpdateAccount.new(github_id: account_github_id, type: type).run

    existing_repo = Repo.find_by(github_id: github_repo.fetch(:id))

    if existing_repo
      update_repo(existing_repo, github_repo, account)
    else
      create_repo(github_repo, account)
    end
  rescue ActiveRecord::RecordNotUnique
    # In the event of a race condition beating us we
    # should be able to find the repo at this point,
    # if not we should raise
    existing_repo = Repo.find_by!(github_id: github_repo.fetch(:id))
    update_repo(existing_repo, github_repo, account)
  end

  private

  def update_repo(existing_repo, github_repo, account)
    existing_repo.update!(
      name: github_repo.fetch(:name),
      private: github_repo.fetch(:private),
      primary_language: github_repo.fetch(:language)&.downcase,
      default_branch: github_repo.fetch(:default_branch),
      account: account,
    )
    existing_repo
  end

  def create_repo(github_repo, account)
    repo = Repo.create!(
      account: account,
      github_id: github_repo.fetch(:id),
      name: github_repo.fetch(:name),
      private: github_repo.fetch(:private),
      primary_language: github_repo.fetch(:language)&.downcase,
      default_branch: github_repo.fetch(:default_branch),
      unreliable_test_suite: false,
      has_ci: true,
    )

    CheckRepoHasCiJob.perform_later(repo: repo)

    repo
  end

  def translate_account_type(account_type)
    case account_type
    when "User" then "user"
    when "Organization" then "org"
    end
  end
end
