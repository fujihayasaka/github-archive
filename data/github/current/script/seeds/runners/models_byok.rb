# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This keeps the boot time of our seeds low.

module Seeds
  class Runner
    class ModelsByok < Seeds::Runner
      def self.help
        <<~HELP
        Creates custom keys and custom models for Models BYOK (Bring Your Own Key) development.

        - by default creates 5 openai custom keys, each with 6 models.

        Requires that github/kredz is running locally and integration app, you may find
        this script/setup-models-byok helpful.
        HELP
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"
        require "diet_earthsmoke"
        new.run(options)
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def run(options)
        clean_up if options[:pristine]

        org_user_pairs = [[github_org, monalisa]]

        org_user_pairs.each do |org, user|
          index_offset = org.models_custom_keys.count
          puts "\nCreating custom keys for @#{org.display_login}..."
          5.times do |i|
            name = "my_custom_key_#{i + 1 + index_offset}"
            puts "Creating custom key #{name}..."
            create_openai_custom_key_with_models(name, user: user, org: org)
          end

          puts "Visit #{GitHub.url}/organizations/#{org.to_param}/settings/custom-models " \
            "and log in as #{user.display_login}."
        end
      end

      private

      sig { params(name: String, user: ::User, org: ::Organization).returns(::ModelsByok::CustomKey) }
      def create_openai_custom_key_with_models(name, user:, org:)
        custom_key = FactoryBot.create(:models_byok_custom_key, :openai, organization: org, name: name, actor: user)

        unless custom_key.create_secret(actor: user, api_key: encrypt_plaintext(Random.alphanumeric(24), org))
          raise "Failed to create secret for custom key"
        end

        puts "#{custom_key.name} created with kredz_key: #{custom_key.kredz_key}"

        custom_model_attrs = 6.times.map do |i|
          model_name = "my_custom_model_#{i + 1}"
          slug = model_name.parameterize
          display_name = (i + 1).even? ? slug : model_name
          { name: display_name, slug: slug, copilot_chat_enabled: (i + 1).odd? }
        end
        custom_model_attrs.each do |attrs|
          puts "\tCreating custom model #{attrs[:name]}..."
          custom_model = custom_key.custom_models.create(attrs)
          unless custom_model.persisted?
            puts "Could not create custom model: #{custom_model.errors.full_messages.to_sentence}"
          end
        end

        custom_key.reload
      end

      sig { returns ::Organization }
      def github_org
        @github_org ||= ::Organization.find_by_login("github") || Seeds::Objects::Organization.create(login: "github",
          admin: monalisa)
      end

      sig { returns ::User }
      def monalisa
        @monalisa ||= Seeds::Objects::User.monalisa
      end

      sig { void }
      def clean_up
        ::ModelsByok::CustomKey.destroy_all
        ::ModelsByok::CustomModel.destroy_all
      end

      sig { params(plaintext: String, owner: ::Organization).returns(String) }
      def encrypt_plaintext(plaintext, owner)
        public_key_id, encoded_public_key = ::ModelsByok::CustomKey.encryption_public_key(owner)
        # Encrypt the secret as the client would, per https://developer.github.com/v3/actions/secrets/#example-encrypting-a-secret-using-ruby
        public_key = RbNaCl::PublicKey.new(Base64.decode64(encoded_public_key))
        box = RbNaCl::Boxes::Sealed.from_public_key(public_key)
        encrypted = box.encrypt(plaintext)
        Base64.strict_encode64(encrypted)
      end
    end
  end
end
