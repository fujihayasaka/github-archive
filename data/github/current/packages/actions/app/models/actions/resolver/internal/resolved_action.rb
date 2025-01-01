# typed: true
# frozen_string_literal: true

class Actions::Resolver::Internal::ResolvedAction < T::Struct
  extend T::Sig

  prop :requested_name, String
  prop :resolved_name, String

  prop :ref, String             # Ref the workflow asked for
  prop :resolved_ref, String    # Ref we resolved and ended up serving

  prop :resolved_sha, String

  prop :tar_url, String
  prop :zip_url, String
  prop :visibility, Symbol

  # Only for a Repo action
  prop :id, T.nilable(Integer) # Repository ID

  # Only for a Package Action
  prop :package_id, T.nilable(Integer)

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_rest_response
    {
      name: requested_name,
      resolved_name: resolved_name,
      resolved_sha: resolved_sha,
      tar_url: tar_url,
      zip_url: zip_url,
      version: ref,
      visibility: visibility,
    }.compact
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_twirp_response
    strategy = if package_id
      MonolithTwirp::Actions::Core::V1::ResolveStrategy.lookup(MonolithTwirp::Actions::Core::V1::ResolveStrategy::RESOLVE_STRATEGY_PACKAGE)
    else
      MonolithTwirp::Actions::Core::V1::ResolveStrategy.lookup(MonolithTwirp::Actions::Core::V1::ResolveStrategy::RESOLVE_STRATEGY_REPOSITORY)
    end

    action = {
      id: id,
      name: requested_name,
      resolved_name: resolved_name,
      resolved_sha: resolved_sha,
      tar_url: tar_url,
      zip_url: zip_url,
      ref: ref,
      visibility: visibility,
      resolve_strategy: T.must(strategy),
    }

    {
      resolved_action: action.compact
    }
  end
end
