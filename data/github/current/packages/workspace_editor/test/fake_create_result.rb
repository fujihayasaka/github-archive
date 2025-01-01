# typed: true
# frozen_string_literal: true

class FakeCreateResult
  include FactoryBot::Syntax::Methods
  include CloudEnvironments::ICreateResult

  sig { params(owner: T.nilable(::User), repository_id: T.nilable(Integer), pull_request: T.nilable(PullRequest), provisioned: T::Boolean).void }
  def initialize(
    owner:,
    repository_id:,
    pull_request:,
    provisioned: true
  )
    @owner = owner
    @repository_id = repository_id
    @pull_request = pull_request
    @provisioned = provisioned
    if @provisioned
      @github_token = "abc"
      @github_token_valid_after = Time.now.to_f
    end
  end

  sig { override.returns(CloudEnvironments::ICloudEnvironment) }
  def cloud_environment
    return @cloud_environment if defined?(@cloud_environment)

    @cloud_environment = create(:cloud_environment, owner: @owner, repository_id: @repository_id, pull_request: @pull_request)
    @cloud_environment.tap { |ce| ce.update(guid: SecureRandom.uuid, state: :provisioned) }
  end

  sig { override.returns(T.nilable(Codespaces::Environment)) }
  def env
    return nil unless @cloud_environment
    ::Codespaces::Environment.from_json({ "id" => @cloud_environment.guid, "connection" => {} })
  end

  sig { override.returns(T.nilable(String)) }
  attr_reader :github_token

  sig { override.returns(T.nilable(Float)) }
  attr_reader :github_token_valid_after

  sig { override.returns(T::Boolean) }
  def provisioned?; @provisioned; end
end
