# typed: true
# frozen_string_literal: true

class GitHubUI::StaffbarVersionComponent < ApplicationComponent
  def hcs?
    ENV["HCS"] == "1"
  end

  def current_url
    url = URI.parse(T.must(request).url)

    query_params = T.must(request).query_parameters.dup
    query_params["_ui_sha"] = GitHubUI::Version.current_ref

    url.query = query_params.to_query
    url.to_s
  end
end
