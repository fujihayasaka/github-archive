# typed: true
# frozen_string_literal: true

class CodeNavigation
  # Known states based on availability of the code nav service, indexing
  # status, and if the blob is in one of the supported code nav langauges.
  STATES = [
    :ok,
    :error_index_not_found,
    :error_index_unreachable,
    :error_internal,
    :index_requested,
  ]

  # Public: Load code navigation symbols for the given repository
  def self.load(current_repository:, current_user:, tree_name:, commit_oid:, path:, language:)
    if ref = current_repository.refs.find(tree_name)
      ref = ref.qualified_name
    end
    response = GitHub::Aleph.find_symbols_for_path(
      repo: current_repository,
      sha: commit_oid,
      path: path,
      ref: ref
    )
    return new(:error_index_unreachable, current_repository, current_user, tree_name) if response.nil?

    state, symbols = if response.error
      if response.error.code == :not_found
        [:error_index_not_found, nil]
      else
        [:error_internal, nil]
      end
    else
      [:ok, response.data.tags]
    end

    new(state, current_repository, current_user, tree_name, code_symbols: symbols)
  end

  def initialize(state, current_repository, current_user, tree_name, code_symbols: nil)
    @state = state
    @current_repository = current_repository
    @current_user = current_user
    @tree_name = tree_name
    @code_symbols = code_symbols || []
    @code_nav_context = :BLOB_VIEW
    @backend = :ALEPH_PRECISE
  end

  attr_reader :backend, :state, :current_repository, :current_user, :tree_name, :commit_oid, :code_symbols, :code_nav_context

  def has_code_symbols?
    state == :ok
  end
end
