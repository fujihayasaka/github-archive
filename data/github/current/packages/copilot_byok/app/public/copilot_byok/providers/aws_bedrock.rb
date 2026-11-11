# typed: strict
# frozen_string_literal: true

class CopilotByok::Providers::AwsBedrock
  sig do
    params(
      access_key: String,
      secret_access_key: String,
      region: T.nilable(String)
    ).returns(T::Array[CopilotByok::Types::SelectorCustomModel])
  end
  def self.fetch_models(access_key:, secret_access_key:, region: nil)
    new(access_key: access_key, secret_access_key: secret_access_key, region: region).fetch_inference_policy_models
  end

  DEFAULT_REGION = "us-west-2"
  INFERENCE_PROFILE_INFERENCE_TYPE = "INFERENCE_PROFILE"
  ON_DEMAND_INFERENCE_TYPE = "ON_DEMAND"

  # access_key - the AWS access key for the AWS user
  # secret_access_key - the AWS secret access key for the AWS user
  sig { params(access_key: String, secret_access_key: String, region: T.nilable(String)).void }
  def initialize(access_key:, secret_access_key:, region: nil)
    @region = T.let(region.presence || DEFAULT_REGION, String)
    @service = T.let("bedrock", String)
    @endpoint = T.let("https://bedrock.#{@region}.amazonaws.com", String)
    @credentials = T.let(Aws::Credentials.new(access_key, secret_access_key), Aws::Credentials)
    @connection = T.let(new_connection, ::GitHub::FaradayClient::External)
  end

  sig { returns(T::Array[CopilotByok::Types::SelectorCustomModel]) }
  def fetch_inference_policy_models
    # Get raw model data
    models = fetch_models
    return [] if models.empty?

    # Get inference profiles for INFERENCE_PROFILE models
    inference_profiles = fetch_inference_profiles

    models
      .map { |model| build_inference_policy_model(aws_bedrock_model: model, inference_profiles: inference_profiles) }
      .compact
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def fetch_models
    # byOutputModality=TEXT filters for models that can generate text output
    params = { byOutputModality: "TEXT" }

    # https://docs.aws.amazon.com/bedrock/latest/APIReference/API_ListFoundationModels.html
    resp = @connection.get("/foundation-models", params)
    raise CopilotByok::Providers::UnauthorizedError, resp.body["message"] if resp.status == 403
    return [] unless resp.success?

    models = resp.body["modelSummaries"] || []

    # Additional client-side filter for models that support converse API
    # This ensures we only return models suitable for chat/completions
    conversational_models = models.select do |model|
      model["converse"] && !model["converse"].nil?
    end

    conversational_models
  end

  sig { returns T.nilable(T::Hash[String, T.untyped]) }
  def fetch_inference_profiles
    # https://docs.aws.amazon.com/bedrock/latest/APIReference/API_ListInferenceProfiles.html
    resp = @connection.get("/inference-profiles")
    raise CopilotByok::Providers::UnauthorizedError, resp.body["message"] if resp.status == 403
    resp.success? ? resp.body : nil
  end

  private

  sig do
    params(
      aws_bedrock_model: T::Hash[String, T.untyped],
      inference_profiles: T.nilable(T::Hash[String, T.untyped])
    ).returns(T.nilable(CopilotByok::Types::SelectorCustomModel))
  end
  def build_inference_policy_model(aws_bedrock_model:, inference_profiles:)
    inference_types = aws_bedrock_model["inferenceTypesSupported"] || []
    model_id = aws_bedrock_model["modelId"]

    if inference_types.include?(INFERENCE_PROFILE_INFERENCE_TYPE) && inference_profiles
      # Handle INFERENCE_PROFILE models - merge with profile data for regions
      matching_profiles = matching_inference_profiles_for(inference_profiles["inferenceProfileSummaries"],
        model_id: model_id)

      if matching_profiles&.any?
        # Extract all regions from matching profiles
        regions = T.let([], T::Array[String])
        inference_arn = T.let(nil, T.nilable(String))

        matching_profiles.each do |profile|
          inference_arn ||= profile["inferenceProfileArn"]
          regions.concat(profile_regions_from(profile["models"]))
        end

        aws_bedrock_model_to_custom_model(aws_bedrock_model,
          inference_policy_regions: regions.uniq,
          inference_type: INFERENCE_PROFILE_INFERENCE_TYPE,
          inference_policy_arn: inference_arn,
        )
      else
        # No matching profiles, add as regular model
        aws_bedrock_model_to_custom_model(aws_bedrock_model, inference_type: ON_DEMAND_INFERENCE_TYPE)
      end
    elsif inference_types.include?(ON_DEMAND_INFERENCE_TYPE)
      # Handle ON_DEMAND models
      aws_bedrock_model_to_custom_model(aws_bedrock_model, inference_type: ON_DEMAND_INFERENCE_TYPE)
    end
  end

  sig do
    params(
      inference_profile_summaries: T.nilable(T::Array[T::Hash[String, T.untyped]]),
      model_id: String
    ).returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
  end
  def matching_inference_profiles_for(inference_profile_summaries, model_id:)
    return unless inference_profile_summaries

    inference_profile_summaries.select do |profile|
      profile_models = profile["models"]
      next false unless profile_models

      profile_models.any? do |profile_model|
        model_arn = profile_model["modelArn"]
        next false unless model_arn

        model_id_from_arn = model_arn.split("/").last
        model_id_from_arn == model_id
      end
    end
  end

  # Private: Given a list of models from the AWS Bedrock API, returns a list of regions those models are in,
  # such as `["us-west-2", "us-east-1"]`.
  sig { params(models: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[String]) }
  def profile_regions_from(models)
    return [] unless models

    profile_regions = models.map do |profile_model|
      model_arn = profile_model["modelArn"]
      next unless model_arn

      # Extract region from ARN, e.g., an ARN like
      # "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-opus-4-5-20251101-v1:0" gives region "us-east-2"
      arn_parts = model_arn.split(":")
      arn_parts[3]
    end
    profile_regions.compact.reject(&:empty?)
  end

  sig do
    params(
      model: T::Hash[String, T.untyped],
      inference_type: String,
      inference_policy_arn: T.nilable(String),
      inference_policy_regions: T.nilable(T::Array[String])
    ).returns(CopilotByok::Types::SelectorCustomModel)
  end
  def aws_bedrock_model_to_custom_model(model, inference_type:, inference_policy_arn: nil, inference_policy_regions: nil)
    # Handle potentially missing releaseDate
    release_date = model.dig("description", "releaseDate")
    created_at = release_date ? Time.parse(release_date).utc : nil
    additional_data = CopilotByok::ProviderData::CustomModel::AwsBedrock.build!({
      "inference_policy_regions" => inference_policy_regions,
      "inference_type" => inference_type,
      "model_arn" => model["modelArn"],
      "inference_policy_arn" => inference_policy_arn,
    })

    CopilotByok::Types::SelectorCustomModel.new(
      name: model["modelName"],
      slug: model["modelId"],
      createdAt: created_at,
      maxOutputTokens: model.dig("converse", "maxTokensMaximum"),
      additionalData: additional_data.to_h,
    )
  end

  sig { returns ::GitHub::FaradayClient::External }
  def new_connection
    ::GitHub::FaradayClient::External.new(@endpoint) do |conn|
      conn.use AwsSignatureV4Middleware, credentials: @credentials, service: @service, region: @region
      conn.request :json
      conn.response :json
      conn.options[:timeout] = 60_000
      conn.adapter Faraday.default_adapter
      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats,
        service_name: GitHub::Config::CopilotByok::SERVICE_NAME
    end
  end

  # AWS Signature V4 middleware for Faraday
  class AwsSignatureV4Middleware < ::Faraday::Middleware
    sig { params(app: T.untyped, options: T::Hash[Symbol, T.untyped]).void }
    def initialize(app, options = {})
      super(app)
      @app = T.let(app, T.untyped)
      @credentials = T.let(options[:credentials], Aws::Credentials)
      @service = T.let(options[:service], String)
      @region = T.let(options[:region], String)
    end

    sig { params(env: T.untyped).returns(T.untyped) }
    def call(env)
      sign_request(env)
      @app.call(env)
    end

    private

    sig { params(env: T.untyped).void }
    def sign_request(env)
      # Set required headers before signing
      env.request_headers["Host"] = env.url.host
      env.request_headers["X-Amz-Date"] = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")

      # Calculate body hash
      body = env.body.to_s
      body_hash = Digest::SHA256.hexdigest(body)
      env.request_headers["X-Amz-Content-Sha256"] = body_hash

      # Create the signer
      signer = Aws::Sigv4::Signer.new(service: @service, region: @region, credentials_provider: @credentials)

      # Sign the request
      signature = signer.sign_request(
        http_method: env.method.to_s.upcase,
        url: env.url.to_s,
        headers: env.request_headers.to_h,
        body: body,
      )

      # Apply the signature headers
      signature.headers.each { |k, v| env.request_headers[k] = v }
    end
  end
end
