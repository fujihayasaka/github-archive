# typed: true
# frozen_string_literal: true

module GitHub::Stafftools
  extend self

  # matches github.com/rest/of/the/url with or without http(s)://
  REPO_URL_FORMAT = %r{((http:|https:)*\/*\/*\w*.?github.\w*\/*\S*)}x

  # text: a string containing github.com urls
  # returns [{"owner/repo" => ["url1", "url2"], "owner2/repo2" => ["url3", "url4"]}, ["failed line"]]
  def group_urls_by_nwo_or_user(text)
    data = {}
    failed_lines = []
    text.split("\n").each do |l|
      begin
        match = l.match(REPO_URL_FORMAT)
        if match.nil?
          failed_lines.push(l) unless l.blank?
          next
        end

        match_url = match[0]
        nwo = nwo_from_url(match_url)
        data[nwo] = [] if data[nwo].nil?
        data[nwo].push(match_url)
      rescue NoMethodError
        failed_lines.push(l)
      end
    end
    [data, failed_lines]
  end

  # text: a String containing github.com urls
  # returns {repo1_object => ["url1", "url2"], repo2_object => ["url3", "url4"]}
  def group_urls_by_repo(text)
    data = {}
    repos_w_files, gists_w_files = split_and_sort_gist_repo_files(text)

    ::Gist.where(repo_name: gists_w_files.keys).each do |gist|
      data[gist] = gists_w_files[gist.repo_name]
    end

    ::Repository.with_names_with_owners(repos_w_files.keys).each do |repo|
      data[repo] = repos_w_files[repo.nwo]
    end
    data
  end

  def split_and_sort_gist_repo_files(text)
    repos_w_files = {}
    gists_w_files = {}
    urls_from_text(text).each do |url|
      nwo = nwo_from_url(url)
      if nwo_for_gist?(nwo)
        gist_name = nwo.split("/").last
        gists_w_files[gist_name] = [] unless gists_w_files.fetch(gist_name, false)
        gists_w_files[gist_name] << url
      else
        repos_w_files[nwo] = [] unless repos_w_files.fetch(nwo, false)
        repos_w_files[nwo] << url
      end
    end
    [repos_w_files, gists_w_files]
  end

  def repo_from_nwo(nwo)
    if nwo_for_gist?(nwo)
      ::Gist.find_by(repo_name: nwo.split("/").last)
    else
      ::Repository.with_name_with_owner(nwo)
    end
  end

  def nwo_from_url(url)
    @gist_hostname ||= URI.parse(GitHub.gist_url).hostname
    uri = URI.parse(Addressable::URI.escape(url))

    if uri.hostname == @gist_hostname && @gist_hostname != GitHub.host_name # gist hostname defaults to host_hame if not configured
      "gist/#{T.must(uri.path).split("/")[2]}"
    else
      T.must(T.must(uri.path).split("/")[1, 2]).join("/")
    end
  end

  def nwo_for_gist?(nwo)
    nwo.starts_with?("gist/")
  end

  def repo_from_url(url)
    nwo = nwo_from_url(url)
    repo_from_nwo(nwo)
  end

  def urls_from_text(text)
    return [] unless text
    text.scan(REPO_URL_FORMAT).map { |u| u[0] }
  end
end
