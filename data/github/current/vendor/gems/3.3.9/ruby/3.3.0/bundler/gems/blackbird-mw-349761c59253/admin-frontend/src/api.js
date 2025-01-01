export function selectCorpus(corpora, name) {
  if (!corpora || !name) {
    return null;
  }
  for (const c of corpora) {
    if (c.corpus_name.toLowerCase() === name.toLowerCase()) {
      return c;
    }
  }
}

export async function getDeployAheadBehind(shas) {
  return post("dotcom", "GetDeployAheadBehind", { commit_shas: shas });
}

export async function listStamps() {
  return post("dotcom", "ListStamps", {}).then((resp) => resp.stamps);
}

export async function getCorpora(stamp) {
  return post(stamp, "GetCorpusStatus", {});
}

// Supports:
// - SetCorpusIndexingState
// - SetCorpusQueryState
// - SetCorpusFilterBlobs
// - SetCorpusHealingState
// - SetEpochDescription
export async function setCorpusState(stamp, method, data) {
  return post(stamp, method, data);
}

export async function getRepo(stamp, owner, name) {
  try {
    const resp = await post(stamp, "GetRepoStatus", { repo_nwo: `${owner}/${name}` });
    return resp;
  } catch (e) {
    if (e.status === 404) {
      let data = await e.json();
      return { failed: true, error: data };
    }
    throw e;
  }
}

export async function setRepo(stamp, method, data) {
  return post(stamp, method, data);
}

export async function getUser(stamp, login) {
  return post(stamp, "GetRateLimitQuota", { login: login });
}

export async function getShardAssignments(stamp, data) {
  try {
    const resp = await post(stamp, "ShardAssignments", data);
    return resp;
  } catch (e) {
    console.log(e);
    return { failed: true, error: e };
  }
}

export async function getClusterHosts(stamp, data) {
  return post(stamp, "ClusterHosts", data);
}

export async function resetUserQuota(stamp, login) {
  return post(stamp, "ResetRateLimitQuota", { login: login });
}

async function post(stamp, name, body) {
  if (!stamp) {
    throw new Error("stamp is required");
  }

  // console.log("calling rpc", name, body);
  const res = await fetch(`/twirp/blackbirdmw.admin.v1.AdminAPI/${name}`, {
    method: "POST",
    body: JSON.stringify(body),
    headers: {
      "Content-Type": "application/json",
      "X-GitHub-Stamp": stamp,
    },
  });
  if (res.ok) {
    let data = await res.json();
    data._rpcMethod = name;
    return data;
  }

  throw res;
}
