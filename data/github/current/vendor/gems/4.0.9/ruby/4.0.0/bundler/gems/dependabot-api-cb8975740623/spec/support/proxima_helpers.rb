# frozen_string_literal: true

module ProximaHelpers
  def stub_proxima_repo_request(repo_id:, fixture:)
    return unless Dependabot.proxima?

    allow(GitHubHelpers).
      to receive(:access_token_for).
      and_return("token")

    repo_url = "#{Dependabot::Application.target_github_internal_api_endpoint}repositories/#{repo_id}"
    stub_request(:get, repo_url).
      to_return(
        status: 200,
        body: fixture("github_responses/#{fixture}.json"),
        headers: { "Content-Type" => "application/json" }
      )
  end
end
