# typed: true
# frozen_string_literal: true

require "diet_earthsmoke"
require "github-kredz"
require "github/kredz_client"
require "test_helper"
require "test_helpers/fake_kredz_response"
require "test_helpers/launch_test_helpers"

module PrivateRegistry
  class SecretTest < GitHub::TestCase
    include ::LaunchTestHelpers

    fixtures do
      create(:private_registry_secrets_integration)
      @org = create(:organization)

      @key = ::DietEarthsmoke::Key.new(::Platform::EncryptionKeys::PRIVATE_REGISTRY_SECRETS).freeze
      @app = ::Apps::Internal.integration(:private_registry_secrets)
    end

    test "can create a private registry secret" do
      secret = build(:private_registry_secret)
      assert secret
    end

    test "can directly modify configuration" do
      secret = build(:private_registry_secret)

      secret.owner = @org

      assert_equal @org, secret.configuration.owner
    end

    context "values dependent on fetching from credz" do
      test "fetches visibility from Credz if nil" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: "test_name",
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        )

        secret = PrivateRegistry::Secret.build(
          owner: @org,
          owner_type: "Organization",
          registry_type: "maven_repository",
          url: "test-url.com",
          name: "test_name"
        )

        Secrets.expects(:fetch).with(
          name: "test_name",
          app: @app,
          owner: @org,
          actor: @org,
          include_value: true
        ).returns(
          GitHub::Launch::Services::Credz::FetchResponse.new(credential: credential)
        )

        assert_equal GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS, secret.visibility
      end

      test "fetches selected_repository_ids from Credz if not defined" do
        repo = create(:repository, owner: @org)
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: "test_name",
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          selected_repositories: [GitHub::Launch::Services::Credz::Repository.new(global_id: repo.global_relay_id)],
          selected_repositories_count: 1,
        )

        secret = PrivateRegistry::Secret.build(
          owner: @org,
          owner_type: "Organization",
          registry_type: "maven_repository",
          url: "test-url.com",
          name: "test_name"
        )

        Secrets.expects(:fetch).with(
          name: "test_name",
          app: @app,
          owner: @org,
          actor: @org,
          include_value: true
        ).returns(
          GitHub::Launch::Services::Credz::FetchResponse.new(credential: credential)
        )

        assert_equal [repo.id], secret.selected_repository_ids
      end

      context "encoded_value" do
        test "fetches encoded value from Credz if nil or not defined" do
          old_secret = build(:private_registry_secret)
          Secrets.stubs(:create).returns(
            GitHub::Launch::Services::Credz::CreateResponse.new(stored: true, credential: nil)
          )
          old_secret.save!

          credential = GitHub::Launch::Services::Credz::Credential.new(
            name: old_secret.name,
            created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
            updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
            value: old_secret.encoded_value,
          )

          secret = PrivateRegistry::Secret.build(
            owner: old_secret.owner,
            owner_type: old_secret.owner_type,
            registry_type: old_secret.registry_type,
            url: old_secret.url,
            name: old_secret.name
          )

          Secrets.expects(:fetch).with(
            name: old_secret.name,
            app: @app,
            owner: old_secret.owner,
            actor: old_secret.owner,
            include_value: true
          ).returns(
            GitHub::Launch::Services::Credz::FetchResponse.new(credential: credential)
          )

          assert_equal old_secret.encoded_value, secret.encoded_value
        end

        test "encoded_value is updated whenever encrypted_value changes" do
          secret = build(:private_registry_secret)
          initial_encoded_value = secret.encoded_value

          secret.encrypted_value = "new value"

          refute_equal initial_encoded_value, secret.encoded_value
        end

        test "the encoded contents make sense and can be decoded" do
          secret = build(:private_registry_secret)
          assert_equal secret.encrypted_value, @key.open(secret.encoded_value, scope: secret.owner.next_global_id)
        end
      end
    end

    context "PrivateRegistry::Secret.build" do
      test "returns a secret" do
        secret = PrivateRegistry::Secret.build(
          owner: @org, owner_type: "Organization",
          registry_type: "maven_repository",
          url: "maven-repository.com",
          name: "test_name",
          encrypted_value: "test_value",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_OWNER
        )

        assert secret
      end
    end

    context "#save!" do
      test "saves a secret" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: "test_name",
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456)
        )

        GitHub::KredzClient::Credz.expects(:create_credential).with do |params|
          expected_params = {
            app: ::Apps::Internal.integration(:private_registry_secrets),
            owner: @org,
            actor: @org,
            key: "test_name",
            visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_OWNER,
            selected_repositories: []
          }

          # DietEarthsmoke::Key#seal is non-deterministic. The sealed value will change even with the same inputs, so
          # we must open it to compare the correct value.
          expected_params <= params && @key.open(params[:value], scope: @org.next_global_id) == "test_value"
        end.returns(
          FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::CreateResponse.new(stored: true, credential: credential))
        )

        secret = PrivateRegistry::Secret.build(
          owner: @org,
          owner_type: "Organization",
          registry_type: "maven_repository",
          url: "maven-repository.com",
          name: "test_name",
          encrypted_value: "test_value",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_OWNER
        )

        assert secret.save!
      end

      test "does not save configuration if secret fails" do
        secret = build(:private_registry_secret)

        Secrets.stubs(:create).returns(
          GitHub::Launch::Services::Credz::CreateResponse.new(stored: false, credential: nil)
        )

        assert_raises(PrivateRegistry::Secret::CreationError) { secret.save! }
        refute secret.configuration.persisted?
      end

      test "does not save secret if configuration fails" do
        secret = build(:private_registry_secret, owner: @org, owner_type: "Organization")

        PrivateRegistry::Configuration.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)
        Secrets.stubs(:create).returns(
          GitHub::Launch::Services::Credz::CreateResponse.new(stored: true, credential: nil)
        )
        Secrets.expects(:delete).with(name: secret.name, owner: @org, actor: @org, app: @app)

        assert_raises(ActiveRecord::RecordInvalid) { secret.save! }
        refute secret.configuration.persisted?
      end
    end

    context "validations" do
      test "validates associated configuration" do
        secret = PrivateRegistry::Secret.build(
          owner: @org,
          owner_type: "Organization",
          registry_type: "maven_repository",
          url: "maven-repository.com",
          name: "test_name",
          encrypted_value: "test_value",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_OWNER
        )

        assert secret.valid?
        secret.configuration.owner = nil
        refute secret.valid?
      end

      test "validates secret name with Credz" do
        secret = PrivateRegistry::Secret.build(
          owner: @org,
          owner_type: "Organization",
          registry_type: "maven_repository",
          url: "maven-repository.com",
          name: "GITHUB_asdf",  # This is an invalid secret name
          encrypted_value: "test_value",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_OWNER
        )

        refute secret.valid?
      end
    end

    context "PrivateRegistry::Secret.for_organization" do
      test "gets list of secrets from the selected org" do
        2.times { create(:private_registry_configuration, owner_id: @org.id, owner_type: "Organization") }

        other_org = create(:organization)
        2.times { create(:private_registry_configuration, owner_id: other_org.id, owner_type: "Organization") }

        secrets = PrivateRegistry::Secret.for_organization(org: @org)

        assert_equal 2, secrets.length
        secrets.each { |secret| assert_equal @org, secret.owner }
      end

      test "if org is nil the query is unaffected" do
        4.times { create(:private_registry_configuration) }

        secrets = PrivateRegistry::Secret.for_organization(org: nil)
        assert_equal 4, secrets.length
      end
    end

    context "PrivateRegistry::Secret.fetch" do
      test "gets the first matching secret and config" do
        config = create(:private_registry_configuration, url: "iwantthisone.com")
        4.times { create(:private_registry_configuration) }

        secret = PrivateRegistry::Secret.fetch(org: config.owner, url: config.url)
        assert_equal "iwantthisone.com", T.must(secret).url
      end
    end
  end
end
