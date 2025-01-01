import type {ItemTrackedByParent, TrackedByItem} from '../../api/issues-graph/contracts'

export function createItemTrackedByParent(item: TrackedByItem): ItemTrackedByParent {
  const {title, state, stateReason, url, number, repoId, repoName, userName, assignees, labels, trackedByTitle} = item
  return {
    ownerId: item.key.ownerId,
    uuid: item.key.primaryKey.uuid,
    itemId: item.key.itemId,
    title,
    state,
    stateReason,
    url,
    displayNumber: number,
    repositoryId: repoId,
    repositoryName: repoName,
    ownerLogin: userName,
    assignees,
    labels,
    position: 0,
    trackedByTitle,
  }
}

export function createTrackedByItem(item: ItemTrackedByParent): TrackedByItem {
  return {
    key: {
      ownerId: item.ownerId,
      itemId: item.itemId,
      primaryKey: {
        uuid: item.uuid,
      },
    },
    title: item.title,
    url: item.url,
    state: item.state,
    repoName: item.repositoryName,
    repoId: item.repositoryId,
    userName: item.ownerLogin,
    number: item.displayNumber,
    labels: item.labels,
    assignees: item.assignees,
    stateReason: item.stateReason,
  }
}
