# typed: true
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class SearchTemplate
    # Supports only 4 words so that search doesn't impact page response.
    MAX_QUERY_WORDS = 4

    class << self
      ## return the templates that matches all words in query with their search score.
      def execute(templates, query)
        if query.nil? || query.empty?
          return templates
        end
        searched_templates = []
        query_hash = convert_search_query_to_patterns(query)
        templates.each do |template|
          categories = template.categories.join(" ") if template.categories
          template_props = [template.id, template.name, template.creator, categories, template.description].compact.join(" ")
          words_matched = 0
          query_hash.each do |word, pattern|
            word_length = word.length * 1.0
            ## Take each word from template_props and call scan method with pattern and then map to array of MatchData https://ruby-doc.org/core-2.4.0/MatchData.html
            ## Regexp.last_match is a global variable that contains MatchData for last regex matched. Regexp.last_match is thread-safe.
            match_datas = template_props.to_enum(:scan, pattern).map { Regexp.last_match }
            if match_datas.empty?
              break
            end

            template.add_weight(calculate_score(match_datas, word_length))
            words_matched += 1
          end
          if words_matched == query_hash.length
            searched_templates << template
          end
        end

        searched_templates
      end

      private

      ## converts the search query to hash of query word and pattern( pattern contains two groups i. start with or space ii. contains queryword)
      def convert_search_query_to_patterns(query)
        keywords = query.split(" ").uniq.slice(0, MAX_QUERY_WORDS)
        hash = {}
        keywords.each do |keyword|
          keyword = keyword.split("@")[0]
          # Removing ruby metacharacters listed here https://ruby-doc.org/core-2.4.1/Regexp.html#class-Regexp-label-Metacharacters+and+Escapes
          if keyword.present?
            keyword.gsub!(/[\\\(\)\[\]\{\}\+\,\*\/]/, "")
            keyword.gsub!(/[\!\.\%\$\&]*\z/, "")
            if keyword.present?
              hash[keyword] = Regexp.new("(\\s+|\\A)(#{keyword}[^.,\\s\\?]*)", Regexp::IGNORECASE)
            end
          end
        end
        hash
      end

      ## calculates the score for each word matched
      ## example: for query word  "no" and template having words: "no", "none", "nodejs"
      ## search score will be max of [ 1 -{length("no") - length("no")}/length("no") ,
      ## 1 - {length("none") - length("no")/length("none")}, 1 -{length("nodejs") - length("no")/length("nodejs")} , that will be 1
      ## data.offset(2) contains the offset of matched word.
      def calculate_score(match_datas, word_length)
        match_datas.reduce(0) { |score, data| [score, 1 - (data.offset(2)[1] - data.offset(2)[0] - word_length).abs / (data.offset(2)[1] - data.offset(2)[0])].max }.round(2)
      end
    end

  end
end
