# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This keeps the boot time of our seeds low.

module Seeds
  class Runner
    class ModelsByok < Seeds::Runner
      include ::ModelsByok::TestHelpers

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
        new.run(options)
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def run(options)
        user, org = create_user_org_pair

        clean_up if options[:pristine]

        puts "\nCreating custom keys..."
        5.times do |i|
          name = "my_custom_key_#{i + 1}"
          puts "Creating custom key #{name}..."
          create_openai_custom_key_with_models(name, user:, org:)
        end
      end

      sig { params(name: String, user: ::User, org: ::Organization).returns(::ModelsByok::CustomKey) }
      def create_openai_custom_key_with_models(name, user:, org:)
        custom_key = org.models_custom_keys.new(
          name: name,
          provider: "openai"
        )

        unless custom_key.valid?
          raise "Custom key is not vald"
        end

        unless custom_key.create_secret(actor: user, api_key: encrypt_plaintext(Random.alphanumeric(24), org))
          raise "Failed to create secret for custom key"
        end

        custom_key.save
        puts "#{custom_key.name} saved with kredz_key #{custom_key.kredz_key}..."

        custom_key.custom_models.create(
          6.times.map do |i|
            model_name = "my_custom_model_#{i + 1}"
            slug = model_name.parameterize
            display_name = (i + 1).even? ? slug : model_name
            puts "\tCreating custom model #{display_name}..."
            { name: display_name, slug: slug, copilot_chat_enabled: (i + 1).odd? }
          end
        )

        custom_key.reload
      end

      private

      sig { returns([::User, ::Organization]) }
      def create_user_org_pair
        user = Seeds::Objects::User.monalisa
        org = Seeds::Objects::Organization.create(login: "github", admin: user)
        [user, org]
      end

      def clean_up
        ::ModelsByok::CustomKey.destroy_all
        ::ModelsByok::CustomModel.destroy_all
      end
    end
  end
end
