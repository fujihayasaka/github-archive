# typed: true
# frozen_string_literal: true

module Codespaces
  class AddDeclarativeSecrets < Command
    # secrets_data: { "secret_name" => "encrypted_value" }
    def initialize(user:, repository:, secrets_data:)
      @user, @repository, @secrets_data = user, repository, secrets_data
    end

    def perform
      @secrets_data.each_with_object({}) do |(secret_name, encrypted_value), results|
        secret = Codespaces::UserSecret.for_user_and_name(@user, secret_name)
        if secret.fetch_credential
          # Secret already exists so we should only be associating it to this repo...
          next if secret.repositories.include?(@repository)

          secret.repository_ids << @repository.id
          results[secret_name] = secret.update
        else
          # Secret doesn't yet exist so we need to create it and associate it to this repo...
          if encrypted_value.blank?
            # Newly created secrets require an encrypted value
            results[secret_name] = false
          else
            secret.encrypted_value = encrypted_value
            secret.repository_ids = [@repository.id]
            results[secret_name] = secret.save
          end
        end
      end
    end
  end
end
