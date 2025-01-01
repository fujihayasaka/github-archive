# typed: true
# frozen_string_literal: true

module ApplicationController::DownloadHeadersDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  private

  sig { params(repo: Repository).void }
  def x_repository_download_header(repo)
    response.headers["X-Repository-Download"] = "git clone #{repo.http_url}"
  end

  sig { params(raw_url: String).void }
  def x_raw_download_header(raw_url)
    response.headers["X-Raw-Download"] = raw_url
  end
end
