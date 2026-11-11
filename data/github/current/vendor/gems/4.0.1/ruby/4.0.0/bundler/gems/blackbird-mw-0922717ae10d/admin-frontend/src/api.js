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
  return post("dotcom", "ListStamps", {})
}

export async function getCorpora(stamp) {
  return post(stamp, "GetCorpusStatus", {});
}

// Supports:
// - SetCorpusIndexingState
// - SetCorpusInstantServingState
// - SetCorpusQueryState
// - SetCorpusFilterBlobs
// - SetCorpusHealingState
// - SetEpochDescription
export async function setCorpusState(stamp, method, data) {
  return post(stamp, method, data);
}

export async function findAnything(stamp, data) {
  return post(stamp, "FindAnything", data);
}

export async function getRepo(stamp, owner, name) {
  return getRepoStatus(stamp, { repo_nwo: `${owner}/${name}` });
}

export async function getRepoById(stamp, id) {
  return getRepoStatus(stamp, { repo_id: id });
}

export async function getRepoStatus(stamp, data) {
  try {
    const resp = await post(stamp, "GetRepoStatus", data);
    return resp;
  } catch (e) {
    if (e.status === 404) {
      let data = await e.json();
      return { failed: true, error: data };
    }
    throw e;
  }
}

export async function getFilesetById(stamp, id) {
  return getFilesetStatus(stamp, { repo_id: id });
}

export async function getFileset(stamp, owner, name) {
  return getFilesetStatus(stamp, { fileset: `${owner}/${name}` });
}

export async function getFilesetStatus(stamp, data) {
  try {
    const resp = await post(stamp, "GetFilesetStatus", data);
    return resp;
  } catch (e) {
    if (e.status === 404) {
      let data = await e.json();
      return { failed: true, error: data };
    }
    throw e;
  }
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

export async function post(stamp, name, body, {useNewErrorHandling} = {}) {
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

  if (useNewErrorHandling) {
    try {
      let data = await res.json();
      return { _rpcMethod: name, error: data, code: res.status, failed: true };
    } catch (e) {
      console.log("failed to parse error response", e);
      return { _rpcMethod: name, error: "failed", code: res.status, failed: true };
    }
  }
  throw res;
}
