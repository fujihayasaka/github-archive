# typed: true
# frozen_string_literal: true

class Site::About::PolicyController < Site::About::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  def index
    render "site/about/developer_policy/index"
  end

  def news # rubocop:todo GitHub/UseRestfulActions
    news = T.let([], T::Array[T.untyped])
    limit = 9
    url = "#{GitHub.blog_url}/policy.json"

    news |= GitHub::JSON::CachedFetchRemoteUrl.fetch(
      url: url,
      cache_key: "about:developer_policy_news:#{url}",
      default_value: [],
      hash_subkey: "items",
    )

    news.sort_by! { |entry| entry["date_published"] }.reverse!

    render "site/about/developer_policy/news/index", locals: { news: news.take(limit) }
  end
end
