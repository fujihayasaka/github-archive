# typed: true
# frozen_string_literal: true

# Provides access to a shared queue of pending changes to be performed over a
# company's team hierarchy
#
# When a team parent changes, the team is moved in the hierarchy and permissions
# for the users inside any team down the one being moved need to be recalculated
#
# Recalculating permissions for hierarchies is a stateful process.
# This means that to recalculate permissions when a team is moved, we need to
# have a snapshot of the hierarchy before it was moved.
#
# As there can be very deep hierarchies with thousands of users, recalculating
# all the permissions can also be time consuming. That's why, to not block them
# until the permissions are recalculated, we mutate hierarchies in two steps:
#
#   * We allow users to change the hierarchy with no restriction, in the
#     foreground.
#
#   * We recalculate permissions in the background, but we need to ensure that
#     the recalculation is consistent, and happens serial (i.e. before
#     permissions are recalculated for change N+1, the recalculation for change N
#     had to be completed)
#
# To guarantee the serial semantics of the last step, we use a queue of pending
# changes per company. `HandleTeamParentChangesJob`
# will check this queue, process the next pending `payload_class`, and enqueue itself
# until the queue is empty.
#
# IMPORTANT: The queue is synchronized using redis mutexes. The current points
# in the code that use the queue are:
#  1. Team::Nested#move_tree_node. Which uses it's own lock mechanism to guarantee
#  that the queue is populated in the right order.
#  2. HandleTeamParentChangesJob, which extends HashLock
#  to for job uniqueness per org, to guarantee that the queue is consumed in the right
#  order.
#
# But even when the queue is produced and consumed in the right order, as it is implemented
# over KV, serializing the whole queue in a single key for simplicity, we need to also
# guarantee that if 1. and 2. above race, they don't overwrite each other changes.
#
module Team::ParentChange
  class PendingQueue < GitHub::DataStructures::PersistentAtomicQueue
    def initialize(org_id:)
      super(queue_type: "team/parent_change/pending", queue_name: org_id, payload_class: Payload)
    end
  end
end
