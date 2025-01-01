# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  module Public
    extend T::Sig

    sig do
      params(
        owner: User,
        repository_id: Integer,
        pull_request_number: Integer,
        location: String,
        operation: Codespaces::AsyncOperation,
        display_name: T.nilable(String),
        devcontainer_path: T.nilable(String),
        sku_name: T.nilable(String),
        vscs_target: T.nilable(String),
        vscs_target_url: T.nilable(String),
        entry_point: T.nilable(String)
      ).returns(IFindOrCreateResult)
    end
    def self.find_or_create(
      owner:,
      repository_id:,
      pull_request_number:,
      location:,
      operation:,
      display_name: nil,
      devcontainer_path: nil,
      sku_name: nil,
      vscs_target: nil,
      vscs_target_url: nil,
      entry_point: nil
    )
      FindOrCreate.call(
        owner:,
        repository_id:,
        pull_request_number:,
        operation:,
        location:,
        display_name:,
        devcontainer_path:,
        sku_name:,
        vscs_target:,
        vscs_target_url:,
        entry_point:
      )
    end
  end
end
