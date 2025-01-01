# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class SearchView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :user

      def page_title
        "#{user.login} - Search"
      end

      def search_record
        return @search_record if defined? @search_record

        index = Elastomer::Indexes::Users.primary
        result = index.docs.get(type: "user", id: user.id)

        @search_record =
            if result["found"]
              source = result["_source"]
              source["_id"] = result["_id"]
              source
            end
      rescue ElastomerClient::Client::Error => e
        Failbot.report e
        @search_record = nil
      end

      def search_record_exists?
        !search_record.nil?
      end

      def is_organization?
        search_record_exists? && search_record["organization"]
      end

      def each_entry(&block)
        sr = search_record
        sr.keys.sort.each { |key| block.call(key, sr[key]) }
        self
      end
    end
  end
end
