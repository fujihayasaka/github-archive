# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class BlackbirdView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
        class NotImplemented < StandardError; end

        attr_reader :repository

        def description
          if err = blackbird_status.error
            "Error checking index status: #{err.msg}"
          else
            [
              "Lexical: #{lexical_search_ok? ? "ok" : "not indexed"}",
              "bm25: #{blackbird_repo_status&.bm25_search_ok ? "ok" : "not indexed"}",
              "embeddings: #{semantic_code_search_ok? ? "ok" : "not indexed"}.",
            ].join(", ")
          end
        end

        def lexical_search_ok?
          blackbird_repo_status&.lexical_search_ok
        end

        def semantic_code_search_ok?
          blackbird_repo_status&.semantic_code_search_ok
        end

        def blackbird_repo_status
          blackbird_status.data.repositories.first unless has_error?
        end

        def has_error?
          blackbird_status.error.present?
        end

        def indexing_error
          return nil if blackbird_status.error.present?
          error_msg = T.let(nil, T.nilable(String))
          blackbird_status.data.corpora.each do |corpus|
            next unless corpus.cluster_is_serving
            next unless %w[HYBRID LEXICAL].include?(corpus.cluster_epoch_mode)
            corpus.repositories.first.commits.each do |commit|
              return nil unless commit.status == :INDEX_STATUS_PERMANENT_ERROR
              if commit.permanent_error.present?
                error_msg = "#{commit.permanent_error.error_msg}: #{corpus.corpus_name.downcase}/#{corpus.cluster_name}"
              end
            end
          end
          error_msg
        end

        def blackbird_status
          return @blackbird_status if defined?(@blackbird_status)
          @blackbird_status = ::Search::Blackbird::Client.get_repository_status([repository.id])
        end
      end
    end
  end
end
