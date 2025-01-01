# typed: strict
# frozen_string_literal: true

module Orca
  class Pipeline


    LinguistLangHash = T.type_alias do
      { id: Integer, color: String, name: String, }
    end

    RepoHash = T.type_alias do
      { id: Integer, name: String }
    end

    PipelineHash = T.type_alias do
      {
        id: String,
        actorLogin: T.nilable(String),
        createdAt: T.nilable(String),
        languages: T::Array[LinguistLangHash],
        repositoryCount: Integer,
        stages: T::Array[Orca::PipelineLogs::Stage],
        status: String,
        wasPrivateTelemetryCollected: T::Boolean,
      }
    end

    TRAINING_STATUSES = T.let([
      T.must(GitHub::Orca::PipelineStatus.lookup(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_ENQUEUED)),
      T.must(GitHub::Orca::PipelineStatus.lookup(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_STARTED)),
      T.must(GitHub::Orca::PipelineStatus.lookup(GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED))
    ], T::Array[Symbol])

    include GitHub::Memoizer

    REQUEST_SOURCE_DOTCOM = T.let("dotcom".freeze, String)
    REQUEST_SOURCE_CHATOPS = T.let("chatops".freeze, String)

    sig { returns(GitHub::Orca::PipelineDetails) }
    attr_reader :pipeline_details

    sig { params(organization: Organization).returns(T.nilable(Orca::Pipeline)) }
    def self.latest_completed_pipeline(organization)
      pipeline_details = Orca.client.get_latest_pipeline_details(
        organization: organization,
        status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED
      )
      return if pipeline_details.nil?
      new(pipeline_details)
    end

    sig { params(organization: Organization).returns(T.nilable(Orca::Pipeline)) }
    def self.latest_pipeline(organization)
      pipeline_details = Orca.client.get_latest_pipeline_details(organization: organization)
      return if pipeline_details.nil?
      new(pipeline_details)
    end

    sig { params(pipeline_id: String).returns(T.nilable(Orca::Pipeline)) }
    def self.fetch_by_id(pipeline_id)
      pipeline_details = Orca.client.get_pipeline_details(pipeline_id: pipeline_id)
      return if pipeline_details.nil?
      new(pipeline_details)
    end

    sig { params(actor: User, organization: Organization, pipeline_id: String).returns(String) }
    def self.cancel_pipeline(actor, organization, pipeline_id)
      Orca.client.cancel_pipeline(actor: actor, organization: organization, pipeline_id: pipeline_id)
    end

    sig { params(actor: User, organization: Organization, pipeline_id: String).returns(String) }
    def self.delete_pipeline(actor, organization, pipeline_id)
      Orca.client.delete_pipeline(actor: actor, organization: organization, pipeline_id: pipeline_id)
    end

    sig { params(organization: Organization).returns(T::Array[Orca::Pipeline]) }
    def self.get_pipelines(organization)
      response = Orca.client.get_pipelines(organization: organization)
      return [] if response.nil?
      wrapped = response.pipelines.map do |pipeline|
        p = GitHub::Orca::PipelineDetails.new(
          pipeline: pipeline,
        )
        Orca::Pipeline.new(p)
      end
      wrapped
    end

    sig { params(pipeline_details: GitHub::Orca::PipelineDetails).void }
    def initialize(pipeline_details)
      @pipeline_details = pipeline_details
    end

    sig { returns(String) }
    def pipeline_id
      pipeline.id
    end

    sig { returns(T.nilable(User)) }
    memoize def actor
      return nil if pipeline.request_actor.nil?
      organization.admins.find_by_id(T.must(pipeline.request_actor).id)
    end

    sig { returns(T.nilable(String)) }
    def actor_login
      pipeline.request_actor&.login # rubocop:disable GitHub/DoNotAllowLogin
    end

    sig { returns(String) }
    def created_at
      date_to_iso_string(pipeline.created_at)
    end

    sig { returns(Organization) }
    memoize def organization
      Organization.find(T.must(pipeline.organization).id)
    end

    sig { returns(T::Array[Repository]) }
    memoize def repositories
      Repository.where(id: repository_ids).to_a
    end

    sig { returns(Integer) }
    memoize def repository_count
      Repository.where(id: repository_ids).count
    end

    sig { returns(T::Array[Repository]) }
    memoize def org_repositories
      organization.repositories.where(id: training_inputs.repositories.map(&:id)).to_a
    end

    sig { returns(T::Array[String]) }
    memoize def languages
      linguist_languages.map(&:name).flatten.uniq.sort
    end

    # If this is modified and it's needed for the UI, update
    # `pipeline_item_as_json` or `pipeline_details_as_json` accordingly
    sig { returns(PipelineHash) }
    def as_json
      {
        id: pipeline_id,
        actorLogin: actor_login,
        createdAt: date_to_iso_string(pipeline.created_at),
        languages: linguist_languages_as_hash,
        repositoryCount: repository_count,
        status: pipeline.status.to_s,
        stages: stages,
        wasPrivateTelemetryCollected: private_telemetry_collected?,
      }
    end

    sig { returns(T::Boolean) }
    def private_telemetry_collected?
      training_inputs.use_private_telemetry
    end

    sig { returns(T::Boolean) }
    def visible_training_type?
      visible_types = [GitHub::Orca::TrainingType::UNKNOWN, GitHub::Orca::TrainingType::PROD]
      visible_types.include?(training_type)
    end

    private

    sig { params(date: String).returns(String) }
    def date_to_iso_string(date)
      return date if date.empty?
      Time.parse(date).iso8601.to_s
    end

    sig { returns(T::Array[LinguistLangHash]) }
    def linguist_languages_as_hash
      linguist_languages.map do |language|
        {
          id: language.language_id,
          color: language.color,
          name: language.name,
        }
      end
    end

    sig { returns(T::Array[Linguist::Language]) }
    def linguist_languages
      training_inputs.language_filters.map do |language|
        Linguist::Language.find_by_id(language.language_id)
      end
    end

    sig { returns(GitHub::Orca::Pipeline) }
    def pipeline
      T.must(@pipeline_details.pipeline)
    end

    sig { returns(T::Array[Integer]) }
    memoize def repository_ids
      training_inputs.repositories.map(&:id)
    end

    sig { returns(T.nilable(User)) }
    memoize def request_actor
      actor = pipeline.request_actor
      return nil if actor.nil?

      organization.admins.find_by_id(actor.id)
    end

    sig { returns(T::Array[Orca::PipelineLogs::Stage]) }
    def stages
      Orca::PipelineLogs.new(pipeline_details).stages_as_json
    end

    sig { returns(T.any(Symbol, Integer)) }
    def status
      pipeline.status
    end

    sig { returns(GitHub::Orca::PipelineTrainingInputs) }
    def training_inputs
      T.must(pipeline.training_inputs)
    end

    sig { returns(Integer) }
    def training_type
      type = training_inputs.training_type

      return type if type.is_a?(Integer)

      val = GitHub::Orca::TrainingType.resolve(type)
      val.nil? ? GitHub::Orca::TrainingType::UNKNOWN : val
    end
  end
end
