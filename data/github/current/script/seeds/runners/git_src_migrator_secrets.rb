# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class GitSrcMigratorSecrets < Seeds::Runner
      SECRET_NAME = "GPR_PULL_PAT"

      def self.help
        <<~HELP
        Sets up git-src-migrator actions repo secrets for local development

        Specify one or many of the following parameters:
        --gpr_pull_pat_value -> the GPR_PULL_PAT secret value
        HELP
      end

      class << self
        def run(options = {})
          puts "Creating GPR_PULL_PAT secret for git-src-migrator"

          secret = options[:gpr_pull_pat_value] || ENV["GPR_PULL_PAT"]

          unless secret
            puts "No GPR_PULL_PAT secret value provided. Please export GPR_PULL_PAT or pass it as a parameter via --gpr_pull_pat_value"
            return
          end

          create_secret(owner: Seeds::Objects::Organization.github, actor: Seeds::Objects::User.monalisa, name: SECRET_NAME, secret: secret)
        end

        private

        def create_secret(owner:, actor:, name:, secret:)
          public_key_id, encoded_public_key = Secrets.github_public_key(owner: owner, key_name: Platform::EncryptionKeys::CUSTOM_TASKS)

          # Encrypt the secret as the client would, per https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#create-or-update-a-repository-secret
          public_key = RbNaCl::PublicKey.new(Base64.decode64(encoded_public_key))
          box = RbNaCl::Boxes::Sealed.from_public_key(public_key)
          encrypted_secret = box.encrypt(secret)
          value = Secrets.embed(public_key_id, encrypted_secret)

          # format/encode value
          encoded_value = Base64.strict_encode64(value)

          Secrets.store(
            app: GitHub.launch_github_app,
            owner: owner,
            actor: actor,
            name: name,
            value: encoded_value,
            visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS
          )
        end
      end
    end
  end
end
