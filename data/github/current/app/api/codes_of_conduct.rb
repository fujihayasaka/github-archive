# typed: true
# frozen_string_literal: true

class Api::CodesOfConduct < Api::App

  CodesOfConductQuery = PlatformClient.parse <<-'GRAPHQL'
    query {
      codesOfConduct {
        ...Api::Serializer::CodesOfConductDependency::PartialCodeOfConductFragment
      }
    }
  GRAPHQL

  get "/codes_of_conduct", operation_id: "codes-of-conduct/get-all-codes-of-conduct" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    results = platform_execute(CodesOfConductQuery)

    deliver :graphql_code_of_conduct_hash, results.data.codes_of_conduct
  end

  CodeOfConductQuery = PlatformClient.parse <<-'GRAPHQL'
    query($key: String!) {
      codeOfConduct(key: $key) {
        ...Api::Serializer::CodesOfConductDependency::FullCodeOfConductFragment
      }
    }
  GRAPHQL

  get "/codes_of_conduct/:key", operation_id: "codes-of-conduct/get-conduct-code" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    variables = {
      key: params[:key],
    }

    results = platform_execute(CodeOfConductQuery, variables: variables)
    deliver :graphql_code_of_conduct_hash, results.data.code_of_conduct, full: true
  end
end
