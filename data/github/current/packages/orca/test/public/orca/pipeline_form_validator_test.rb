# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../orca_test_helpers"

class OrcaPipelineFormValidatorTest < GitHub::TestCase
  include OrcaTestHelpers

  fixtures do
    enable_feature_flag(:orca_override_training_rate_limit)
    @admin = create(:user)
    @org = create(:copilot_for_business_enabled_organization, admin: @admin)
    @org_owned_repo = create(:private_repository, owner: @org, from_example: :post_receive_job_test)
    @use_private_telemetry = true
  end

  context "#enqueue_pipeline" do
    test "returns a success when it can enqueue" do
      stub_orca_request "StartCustomization",
        GitHub::Orca::StartCustomizationRequest.new(
          dotcom_actor: Orca::Client.actor(@admin),
          organization: Orca::Client.organization(@org),
          repositories: [Orca::Client.repository(@org_owned_repo)],
          use_private_telemetry: @use_private_telemetry
        ),
        GitHub::Orca::StartCustomizationResponse.new(
          pipeline_id: "1234",
        )
      pipeline = Orca::PipelineFormValidator.new(organization: @org, user: @admin, repository_nwos: [@org_owned_repo.nwo], use_private_telemetry: @use_private_telemetry)
      assert pipeline.valid?
      enqueued, id = pipeline.enqueue_pipeline
      assert enqueued
      assert_equal "1234", id
    end

    test "will not enqueue invalid pipeline" do
      value = [create(:repository).nwo, @org_owned_repo.nwo]
      bad_repos = Orca::PipelineFormValidator.new(
        organization: @org, user: @admin, repository_nwos: value, languages: ["ruby"], use_private_telemetry: @use_private_telemetry)
      refute bad_repos.valid?
      enqueued, _ = bad_repos.enqueue_pipeline
      refute enqueued
    end

    test "returns a failure when it cannot connect to orca" do
      stub_orca_request "StartCustomization",
        GitHub::Orca::StartCustomizationRequest.new(
          dotcom_actor: Orca::Client.actor(@admin),
          organization: Orca::Client.organization(@org),
          repositories: [Orca::Client.repository(@org_owned_repo)]
        ),
        Twirp::Error.internal("Internal server error")
      pipeline = Orca::PipelineFormValidator.new(organization: @org, user: @admin, repository_nwos: [@org_owned_repo.nwo], use_private_telemetry: @use_private_telemetry)
      assert pipeline.valid?
      enqueued, _ = pipeline.enqueue_pipeline
      refute enqueued
    end
  end

  context "#repositories" do
    test "returns the repositories" do
      pipeline = Orca::PipelineFormValidator.new(
        organization: @org,
        user: @admin,
        repository_nwos: [@org_owned_repo.nwo],
        use_private_telemetry: @use_private_telemetry,
      )
      assert_equal [@org_owned_repo].map(&:nwo),
        pipeline.repositories.map(&:nwo)
    end

    test "defaults to all organization repos (omits forks and archived)" do
      private_repo = create(:private_repository, owner: @org, name: "private")
      public_repo = create(:repository, owner: @org, name: "public")
      internal_repo = create(:internal_repository, owner: @org, name: "internal")
      create(:fork_repository, owner: @org, name: "forked", forker: @admin, fork_repo: create(:repository))
      create(:archived_repository, owner: @org, name: "archived")

      pipeline = Orca::PipelineFormValidator.new(
        organization: @org,
        user: @admin,
        repository_nwos: [],
        use_private_telemetry: @use_private_telemetry,
      )
      assert pipeline.valid?

      assert_equal [@org_owned_repo, private_repo, public_repo, internal_repo].map(&:nwo).sort,
        pipeline.repositories.map(&:nwo).sort
    end
  end

  context "validations" do
    test "requires the repos to belong to the org" do
      value = [create(:repository).nwo, @org_owned_repo.nwo]
      bad_repos = Orca::PipelineFormValidator.new(
        organization: @org, user: @admin, repository_nwos: value, languages: ["ruby"], use_private_telemetry: @use_private_telemetry)
      refute bad_repos.valid?
      assert_equal bad_repos.errors[:repository_nwos], ["One of the repositories is not owned by the org"]
    end

    test "requires repos to exist" do
      bad_repos = Orca::PipelineFormValidator.new(
        organization: @org, user: @admin, repository_nwos: ["notreal/repo"], languages: ["ruby"], use_private_telemetry: @use_private_telemetry)
      refute bad_repos.valid?
      assert_equal bad_repos.errors[:repository_nwos], ["One of the repositories is not owned by the org"]
    end

    test "bypass nwo with repos directly" do
      w_repos = Orca::PipelineFormValidator.new(
        organization: @org, user: @admin, repository_nwos: nil, languages: ["ruby"], use_private_telemetry: @use_private_telemetry)
      w_repos.repositories = @org.repositories.to_a
      assert w_repos.valid?
      assert_equal [@org_owned_repo], w_repos.repositories
    end

    test "validates org ownership when using repos directly" do
      org2 = create(:copilot_for_business_enabled_organization, admin: @admin)
      create(:private_repository, owner: org2, from_example: :post_receive_job_test)
      bad_repos = Orca::PipelineFormValidator.new(
        organization: @org, user: @admin, repository_nwos: nil, languages: ["ruby"], use_private_telemetry: @use_private_telemetry)
      bad_repos.repositories = org2.repositories.to_a
      refute bad_repos.valid?
      assert_equal bad_repos.errors[:repository_nwos], ["One of the repositories is not owned by the org"]
    end

    test "malformed nwo path" do
      bad_repos = Orca::PipelineFormValidator.new(
        organization: @org, user: @admin, repository_nwos: ["notreal"], languages: ["ruby"], use_private_telemetry: @use_private_telemetry)
      refute bad_repos.valid?
      assert_equal bad_repos.errors[:repository_nwos], ["repository_nwos do not include the org", "One of the repositories is not owned by the org"]
    end


    {
      "array of numbers": [1, 2],
      "not an array": 1,
    }.each do |name, languages|
      test "validates languages, #{name}" do
        pipeline_request = Orca::PipelineFormValidator.new(
          organization: @org, user: @admin, repository_nwos: [@org_owned_repo.nwo],
          languages: languages, use_private_telemetry: @use_private_telemetry
        )
        refute pipeline_request.valid?
        assert pipeline_request.errors.include?(:languages)
      end
    end

    [
      [
        "expand ruby",
        ["Ruby"]
      ],

      [
        "lower cased",
        ["python"]
      ],

      [
        "deduplicate",
        %w[Ruby ruby]
      ],

      [
        "remove empty",
        ["ruby", ""]
      ],
      [
        "multiple languages",
        %w[Python ruby]
      ],
      [
        "no language will",
        []
      ],
      [
        "language alias",
        ["common-lisp"]
      ],
      [
        "escaped name",
        ["Common-Lisp"]
      ]
    ].each do |name, input|
      test "normalizes languages, #{name}" do
        pipeline_request = Orca::PipelineFormValidator.new(
          organization: @org,
          user: @admin,
          repository_nwos: [@org_owned_repo.nwo],
          languages: input,
          use_private_telemetry: @use_private_telemetry
        )

        assert pipeline_request.valid?, pipeline_request.errors.messages
      end
    end


    test "languages can be an empty array" do
      r = Orca::PipelineFormValidator.new(
        organization: @org,
        user: @admin,
        repository_nwos: [],
        languages: [],
        use_private_telemetry: @use_private_telemetry
      )
      assert r.valid?, r.errors.messages
      assert_equal r.repositories.pluck(:id).sort, @org.repositories.pluck(:id).sort
    end

    test "default repository id to []" do
      r = Orca::PipelineFormValidator.new(
        organization: @org,
        user: @admin,
        repository_nwos: nil,
        languages: [],
        use_private_telemetry: @use_private_telemetry
      )
      assert r.valid?
      assert_equal r.repositories.pluck(:id).sort, @org.repositories.pluck(:id).sort
    end

    test "normalize string repository nwo to array" do
      r = Orca::PipelineFormValidator.new(
         organization: @org,
         user: @admin,
         repository_nwos: @org_owned_repo.nwo,
         languages: nil,
         use_private_telemetry: @use_private_telemetry
       )
      assert r.valid?
      assert_equal r.repositories.pluck(:id).sort, [@org_owned_repo.id].sort
    end
  end
end
