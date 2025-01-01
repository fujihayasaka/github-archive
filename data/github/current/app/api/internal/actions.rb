# typed: true
# frozen_string_literal: true

class Api::Internal::Actions < Api::Internal
  def externally_accessible?
    false
  end

  def require_request_hmac?
    true
  end

  def authenticated_for_private_mode?
    true
  end

  # This is a POST because it accepts many IDs, and caching is not a concern
  # given that we are unlikely to receive duplicate batches
  post "/internal/actions/abuse-batch-info", operation_id: :internal do
    @route_owner = "@github/actions-launch"

    max_ids = 250
    ids = receive(Hash).fetch("ids")
    if ids.length > max_ids
      deliver_error 422, message: "Cannot process more than #{max_ids}, #{ids.length} sent"
      return
    end

    by_type = Hash.new do |h, k|
      h[k] = []
      h[k]
    end

    ids.each do |id|
      type_name, id = Platform::Helpers::NodeIdentification.from_global_id(id)
      by_type[type_name] << id
    end

    allowed = %w[User Repository Organization Enterprise]
    invalid = by_type.keys - allowed
    if invalid.any?
      deliver_error 422, message: "Global IDs supplied for unexpected types: #{invalid.join(", ")}"
      return
    end

    map_owner = lambda { |o| [global_id(o), ::ActionsPlanOwner.new(o)] }

    # This is done via AR directly as having GraphQL's permission model support this
    # unauthenticated use-case felt like it had the potential to cause security issues.

    # This could be parallelised if this responds too slowly - felt unlikely as it's a low traffic batch
    all_nodes = ActiveRecord::Base.connected_to(role: :reading) do
      by_type.slice(*allowed).flat_map do |type, ids|
        case type
        when "User"
          User.includes(:plan_subscription).where(id: ids).map(&map_owner)
        when "Organization"
          Organization.includes(:plan_subscription).where(id: ids).map(&map_owner)
        when "Enterprise"
          # should not be a n+1 as all businesses share one of two plans
          Business.where(id: ids).map(&map_owner)
        when "Repository"
          repo_promises = Repository.where(id: ids).to_a.map do |repo|
            repo.async_actions_plan_owner.then { |o| [global_id(repo), o] }
          end
          Promise.all(repo_promises).sync
        else
          deliver_error 500, message: "Misconfigured endpoint"
          return
        end
      end
    end

    as_json = Hash[all_nodes].transform_values do |plan_owner|
      {
          id: plan_owner.id,
          database_id: plan_owner.database_id,
          plan_name: plan_owner.plan_name,
          name: plan_owner.name,
          type: plan_owner.type,
      }
    end
    deliver_raw({
      owners_by_id: as_json,
    })
  end

  def global_id(e)
    return e.global_relay_id if GitHub.enterprise?

    e.next_global_id
  end
end
