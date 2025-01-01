# typed: true
# frozen_string_literal: true

require "github-orca"

module OrcaTestHelpers
  extend T::Sig
  include WebMock::API

  sig { params(actor: User, organization: Organization, response: T.untyped, use_private_telemetry: T::Boolean, repositories: T::Array[Repository], languages: T::Array[Linguist::Language]).returns(T.untyped) }
  def stub_orca_start_customization_request(actor:, organization:, response:, use_private_telemetry:, repositories: [], languages: [])
    languages = languages.map do |lang|
      GitHub::Orca::LingustLanguage.new(
        name: lang.name,
        language_id: lang.language_id,
      )
    end
    stub_orca_request "StartCustomization",
        GitHub::Orca::StartCustomizationRequest.new(
          dotcom_actor: Orca::Client.actor(@admin),
          organization: Orca::Client.organization(@organization),
          repositories: [Orca::Client.repository(@repository)],
          language_filters: languages,
          use_private_telemetry: use_private_telemetry,
        ),
       response
  end

  sig { params(method_name: String, request: T.untyped, response: T.untyped).void }
  def stub_orca_request(method_name, request, response)
    case response
    when Twirp::Error
      status = Twirp::ERROR_CODES_TO_HTTP_STATUS[response.code]
      body = response.to_json
      headers = { "Content-Type" => "application/json" }
    else
      status = 200
      body = response.to_proto
      headers = { "Content-Type" => "application/protobuf" }
    end

    stub_request(:post, "#{GitHub.orca_base_url}/github.orca.api.v1.OrcaAPI/#{method_name}")
      .with(body: request.to_proto)
      .to_return(
        status: status,
        body: body,
        headers: headers,
      )
  end

  sig { params(date: ActiveSupport::TimeWithZone).returns(String) }
  def orca_date_format(date)
    # Orca date format taken from tests
    # https://github.com/github/orca/blob/63e9e5b2f92d6b92436f5f0ae1939784cb55cfb9/internal/api/service_test.go#L520
    date.strftime("%Y-%m-%d %H:%M:%S %z UTC").to_s
  end

  sig do params(
    organization: Organization,
    repositories: T::Array[Repository],
    actor: T.nilable(User),
    pipeline_id: String,
    languages: T::Array[String],
    status: Symbol
  ).returns(GitHub::Orca::PipelineDetails)
  end
  def orca_pipeline_details(
    organization:,
    repositories:,
    actor: nil,
    pipeline_id: "",
    languages: [],
    status: T.must(GitHub::Orca::PipelineStatus.lookup(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED))
  )
    if pipeline_id.blank?
      pipeline_id = SecureRandom.uuid
    end

    completed_states = [
      GitHub::Orca::PipelineStatus.lookup(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED),
      GitHub::Orca::PipelineStatus.lookup(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_FAILED)
    ]

    created_at = orca_date_format(1.hour.ago)

    started_at = ""
    if status == GitHub::Orca::PipelineStatus.lookup(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED)
      started_at = orca_date_format(1.hour.ago)
    end

    completed_at = ""
    if completed_states.include?(status)
      completed_at = orca_date_format(5.minutes.ago)
    end
    ext = []
    language_filters = languages.map do |lang|
      language = Linguist::Language.find_by_name(lang)
      GitHub::Orca::LingustLanguage.new(
        name: language.name,
        language_id: language.language_id,
      )
    end

    GitHub::Orca::PipelineDetails.new(
      pipeline: GitHub::Orca::Pipeline.new(
        id: pipeline_id,
        organization: Orca::Client.organization(organization),
        status: status,
        status_string: status.to_s,
        created_at: created_at,
        started_at: started_at,
        completed_at: completed_at,
        request_actor: actor ? Orca::Client.actor(actor) : nil,
        training_inputs: GitHub::Orca::PipelineTrainingInputs.new(
          language_filters: language_filters,
          repositories: repositories.map { Orca::Client.repository(_1) }
        ),
      ),
      stages: {
        "test-stage": GitHub::Orca::StageDetails.new(
          summary: GitHub::Orca::StageSummary.new(
            total_count: 1,
            total_count_by_status: {
              "completed": 1
            }
          ),
          details: [
            GitHub::Orca::Stage.new(
              id:        "test-stage",
              status:    GitHub::Orca::PipelineStageStatus.lookup(
                GitHub::Orca::PipelineStageStatus::PIPELINE_STAGE_STATUS_COMPLETED
              ),
              stage_type: "test",
            )
          ]
        )
      },
    )
  end
end
