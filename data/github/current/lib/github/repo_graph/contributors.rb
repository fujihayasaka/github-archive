# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    class Contributors
      include AvatarHelper
      include UrlHelper

      def initialize(repo, cache)
        @repo = repo
        @cache = cache
      end

      attr_reader :cache

      def name
        "contributors"
      end

      def cache_key
        @cache_key ||= "repo-graph:contributors:%s:%s:%s" % [
         "v20.#{AvatarHelper::CACHE_VERSION}",
          @repo.network_id,
          @repo.default_oid,
        ]
      end

      def empty?(check = data)
        check.empty?
      end

      def data
        return [] unless @repo.default_oid

        memo = []
        user_ids = @cache.user_data.map(&:first)
        users = ActiveRecord::Base.connected_to(role: :reading) { User.where(id: user_ids).index_by(&:id) }

        @cache.user_data.each do |user_id, user_data|
          user = users[user_id]
          avatar = avatar_url_for(user, 60)
          path = user_path(user)
          author = {
            "id" => user.id,
            "login" => user.display_login,
            "avatar" => avatar,
            "path" => path,
            "hovercard_url" => HovercardHelper.user_hovercard_path(user_login: user.display_login),
          }
          user_memo = { "author" => author, "total" => user_data.size, "weeks" => [] }
          @cache.weeks.each do |week|
            week_data = user_data.select { |i| i[0] == week }
            user_memo["weeks"] << {
              "w" => week,
              "a" => week_data.sum { |e| e[1] },
              "d" => week_data.sum { |e| e[2] },
              "c" => week_data.size,
            }
          end
          memo << user_memo
        end
        memo.sort_by { |e| e["total"] }.last(100)
      end
    end
  end
end
