import React from "react";
import {
  Box,
  Button,
  FormControl,
  Label,
  Text,
  TextInput,
  Link as PrimerLink,
  ToggleSwitch,
  Tooltip,
  Truncate,
  Checkbox,
  Select,
  Octicon,
  Pagehead,
  Flash,
  Textarea,
} from "@primer/react";
import { TabPanels } from "@primer/react/experimental";
import { useFetcher, Link, useOutletContext } from "react-router-dom";
import { setCorpusState, selectCorpus } from "../../api";
import { useState } from "react";
import {
  SearchIcon,
  CheckIcon,
  PinIcon,
  ClockIcon,
  AlertIcon,
  InfoIcon,
  PencilIcon,
  CloudOfflineIcon,
  DiffRemovedIcon,
  DiffAddedIcon,
} from "@primer/octicons-react";
import { corpusDisplayName, EpochMode } from "../../components/corpus";

export async function action({ request, params }) {
  let formData = await request.formData();
  let data = { corpus: params.name };

  if (formData.get("serving")) {
    data.serving = formData.get("serving") === "true";
  } else if (formData.get("indexing")) {
    data.indexing = formData.get("indexing") === "true";
  } else if (formData.get("healing")) {
    data.healing = formData.get("healing") === "true";
  }

  if (formData.get("serving_ts")) {
    const ts = formData.get("serving_ts");
    let serving_ts = Date.parse(ts);
    if (isNaN(serving_ts)) {
      serving_ts = parseInt(ts, 10);
    }
    data.serving_ts = serving_ts;
  }

  if (formData.get("epoch_id") === "custom") {
    data["epoch_id"] = formData.get("custom_epoch_id");
  } else if (formData.get("epoch_id")) {
    data["epoch_id"] = formData.get("epoch_id");
  }
  if (formData.get("epoch_mode") === "custom") {
    data["epoch_mode"] = formData.get("custom_epoch_mode");
  } else if (formData.get("epoch_mode")) {
    data["epoch_mode"] = formData.get("epoch_mode");
  }
  if (formData.get("num_shards") === "custom") {
    data["num_shards"] = formData.get("custom_num_shards");
  } else {
    data["num_shards"] = formData.get("num_shards")
  }

  setIfBool(data, formData, "bootstrap");
  setIfBool(data, formData, "force");
  setIf(data, formData, "cluster");
  setIf(data, formData, "percent");
  setIf(data, formData, "cache_cluster");
  setIf(data, formData, "description");

  setIf(data, formData, "source_epoch");
  setIf(data, formData, "source_corpus");
  setIf(data, formData, "branch_ts");
  setIfArray(data, formData, "repo_ids");

  const rpcMethod = formData.get("rpcMethod");
  return setCorpusState(params.stamp, rpcMethod, data);
}

export function Corpus() {
  const { corpora, corpus, deployEnv } = useOutletContext();
  const [filter, setFilter] = useState("");
  const fetcher = useFetcher();

  let numServingCorpora = 0;
  for (const c of corpora) {
    if (c.serving) {
      numServingCorpora++;
    }
  }
  const anotherCorpusServing = numServingCorpora > 1;
  const isCacheCluster = corpus.cluster_name.includes("cache");
  const maxRepos = parseInt(corpus.max_repos_indexed).toLocaleString();

  return (
    <Box flexGrow={1}>
      <Box display="flex" flexDirection="column">
        <ColorBar snapshot={corpus.snapshot} isCacheCluster={isCacheCluster} />
        {isCacheCluster ? (
          <Box display="flex" flexDirection="column">
            <Pagehead sx={{ pb: 2, mb: 2 }}>{corpus.corpus_name} cluster</Pagehead>
            <Text color="fg.subtle" fontSize={1} display="block" sx={{ mb: 2 }}>
              <b>Serving epoch:</b> {corpus.epoch_id}
              {!corpus.active_epoch && (
                <Text sx={{ mx: 2, color: "danger.fg" }}>
                  <Octicon icon={CloudOfflineIcon} /> This epoch is no longer active — load a newer one
                </Text>
              )}
              <br />
              <b>Epoch mode:</b> {corpus.epoch_mode}
              <br />
              <b>Description:</b> {corpus.epoch_description}
              <br />
              <b>Num hosts:</b> {corpus.snapshot?.host_assignments.length}
              <br />
              <b>Num shards:</b> {corpus.num_shards}
              <br />
              <b>Index version:</b> {corpus.index_version}
              <br />
              <b>Repos indexed (est.):</b> {maxRepos}
            </Text>

            <Text fontWeight="bold">Change epoch</Text>
            <Text color="fg.subtle" fontSize={1} display="block" sx={{ mb: 2 }}>
              Changing the epoch of a cache cluster can take a up to an hour.
            </Text>
            <ChangeEpoch fetcher={fetcher} corpora={corpora} corpus={corpus} />

            <HostsSection corpus={corpus} filter={filter} setFilter={setFilter} />
          </Box>
        ) : (
          <Box sx={{ display: "flex", flexDirection: "column" }}>
            <Box>
              <Pagehead sx={{ pb: 2, mb: 2 }}>Manage {corpusDisplayName(corpus)}</Pagehead>

              <EpochDescription fetcher={fetcher} corpus={corpus} />

              <Text color="fg.subtle" fontSize={1} display="block" sx={{ mb: 2 }}>
                <b>Epoch:</b> {corpus.epoch_id}
                <br />
                <b>Epoch mode:</b> {corpus.epoch_mode}
                <br />
                <b>Index version:</b> {corpus.index_version}
                <br />
                <b>Num hosts:</b> {corpus.snapshot?.host_assignments.length}
                <br />
                <b>Num shards:</b> {corpus.num_shards}
                <br />
                <b>Repos indexed (est.):</b> {maxRepos}
              </Text>
            </Box>

            <ClusterStatuses fetcher={fetcher} corpus={corpus} anotherCorpusServing={anotherCorpusServing} />

            <SetCacheCluster corpus={corpus} corpora={corpora} fetcher={fetcher} />

            <TabPanels sx={{ mt: 4 }} aria-label="Configure this cluster">
              <TabPanels.Tab>Branch</TabPanels.Tab>
              <TabPanels.Panel>
                <BranchEpoch corpus={corpus} corpora={corpora} fetcher={fetcher} deployEnv={deployEnv} />
              </TabPanels.Panel>
              <TabPanels.Tab>Backfill</TabPanels.Tab>
              <TabPanels.Panel>
                <Backfill corpora={corpora} corpus={corpus} fetcher={fetcher} deployEnv={deployEnv} />
              </TabPanels.Panel>
              <TabPanels.Tab>Pin</TabPanels.Tab>
              <TabPanels.Panel>
                <Pin corpus={corpus} fetcher={fetcher} />
              </TabPanels.Panel>
              <TabPanels.Tab>Force Bootstrap</TabPanels.Tab>
              <TabPanels.Panel>
                <ForceBootstrap corpus={corpus} fetcher={fetcher} />
              </TabPanels.Panel>
            </TabPanels>

            <HostsSection corpus={corpus} filter={filter} setFilter={setFilter} />

            <IndexRepoList corpora={corpora} fetcher={fetcher} />
          </Box>
        )}

        <Pagehead sx={{ pb: 2, mb: 2 }}>Raw JSON</Pagehead>
        <Box sx={{ overflow: "auto" }}>
          <pre>{JSON.stringify(corpus, null, 2)}</pre>
        </Box>
      </Box>
    </Box>
  );
}

function EpochDescription({ fetcher, corpus }) {
  const [isEditing, setIsEditing] = useState(false);

  return isEditing ? (
    <Box sx={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
      <fetcher.Form method="post" onSubmit={() => setIsEditing(false)}>
        <input type="hidden" name="rpcMethod" value="SetEpochDescription"></input>
        <input type="hidden" name="epoch_id" value={corpus.epoch_id}></input>
        <FormControl required>
          <Box sx={{ my: 2, display: "flex", alignItems: "center" }}>
            <FormControl.Label visuallyHidden>Description</FormControl.Label>
            <TextInput
              aria-label="Description"
              name="description"
              minWidth={350}
              defaultValue={corpus.epoch_description}
            />
            <Box sx={{ display: "flex", alignItems: "center" }}>
              <Button type="submit" variant="primary" size="small" sx={{ mx: 2 }}>
                Save description
              </Button>
              <Button size="small" variant="outline" onClick={() => setIsEditing(!isEditing)}>
                Cancel
              </Button>
            </Box>
          </Box>
        </FormControl>
      </fetcher.Form>
    </Box>
  ) : (
    <Box sx={{ display: "flex", alignItems: "center" }}>
      <Text sx={{ fontSize: 1, color: "fg.subtle", mr: 1 }}>{corpus.epoch_description}</Text>
      <Button size="small" variant="invisible" onClick={() => setIsEditing(!isEditing)}>
        <Octicon icon={PencilIcon} />
      </Button>
    </Box>
  );
}

function ShadowTraffic({ fetcher, corpus }) {
  const [percent, setPercent] = useState(corpus.shadow_traffic_percent);
  const didSet = fetcher.data?._rpcMethod === "SetCorpusShadowTraffic";

  return (
    <Box sx={{ mt: 2 }}>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="SetCorpusShadowTraffic"></input>
        <input type="hidden" name="corpus" value={corpus.corpus_name}></input>
        <Text sx={{ fontSize: 1, fontWeight: "bold" }}>Shadow Traffic (0.0 - 1.0)*</Text>
        <Box sx={{ mt: 1, display: "flex", alignItems: "center" }}>
          <FormControl required>
            <FormControl.Label visuallyHidden>Shadow Traffic Percent (0.0 - 1.0)</FormControl.Label>
            <TextInput
              aria-label="Percent"
              name="percent"
              placeholder={0.0}
              defaultValue={percent}
              sx={{ maxWidth: 120 }}
            />
          </FormControl>
          <Button sx={{ ml: 2 }} type="submit" onClick={(e) => setPercent(e.target.value)}>
            Save
          </Button>
          {didSet && (
            <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
              <Octicon icon={CheckIcon} /> Success! Shadow traffic updated.
            </Text>
          )}
        </Box>
      </fetcher.Form>
    </Box>
  );
}

function ToggleForm({ fetcher, name, value, caption, rpcMethod, disabled = false, sx, children }) {
  const [checked, setChecked] = useState(value);
  const onClick = () => setChecked(!checked);
  const capitalName = name[0].toUpperCase() + name.slice(1);

  return (
    <Box display="flex" alignItems="center" sx={sx}>
      <Box flexGrow={1}>
        <Text fontSize={2} fontWeight="bold" id={`is${capitalName}Id`} display="block">
          {capitalName}
        </Text>
        <Box sx={{ display: "flex" }}>
          <Text color="fg.subtle" fontSize={1} id={`is${capitalName}Caption`} display="block" sx={{ mr: 1 }}>
            {caption}
          </Text>
          {children}
        </Box>
      </Box>
      <fetcher.Form method="post">
        <input type="hidden" name={name} value={checked} />
        <input type="hidden" name="rpcMethod" value={rpcMethod} />
        <ToggleSwitch
          disabled={disabled}
          checked={checked}
          aria-labelledby={`is${capitalName}Label`}
          onClick={onClick}
        />
      </fetcher.Form>
    </Box>
  );
}

function ClusterStatuses({ fetcher, corpus, anotherCorpusServing }) {
  const [isServing, setIsServing] = useState(corpus.serving);
  const [force, setForce] = useState(false);
  const disabled = corpus.serving && !anotherCorpusServing && !force;

  return (
    <Box>
      <Box display="flex" alignItems="center">
        <Box flexGrow={1}>
          <Text fontSize={2} fontWeight="bold" id="isServingId" display="block">
            Serving
          </Text>
          <Box sx={{ display: "flex" }}>
            <Text color="fg.subtle" fontSize={1} id="isServingCaption" display="block" sx={{ mr: 1 }}>
              Should this cluster serve queries?
            </Text>
            {!corpus.serving && corpus.ingest_mode !== "Incremental" && (
              <Text fontSize={1} sx={{ color: "attention.emphasis" }}>
                <Octicon icon={AlertIcon} /> Usually best to wait until the backfill is complete.
              </Text>
            )}
          </Box>
        </Box>
        <fetcher.Form method="post">
          <input type="hidden" name="serving" value={isServing} />
          <input type="hidden" name="force" value={force} />
          <input type="hidden" name="rpcMethod" value="SetCorpusQueryState" />
          <ToggleSwitch
            disabled={disabled}
            checked={isServing}
            aria-labelledby="isServingLabel"
            onClick={() => setIsServing(!isServing)}
          />
        </fetcher.Form>
      </Box>
      {corpus.serving && !anotherCorpusServing && (
        <Box sx={{ display: "flex", alignItems: "center", mt: 1 }}>
          <FormControl>
            <FormControl.Label>
              <Text>Force disable serving</Text>
            </FormControl.Label>
            <Checkbox
              aria-label="force"
              name="force"
              value={force}
              checked={force}
              onChange={(e) => setForce(e.target.checked)}
            />
            <FormControl.Caption>
              <Text fontSize={1} sx={{ color: "attention.emphasis" }}>
                <Octicon icon={AlertIcon} sx={{ mr: 2 }} />
                Warning: this is the only serving cluster right now.
                <Octicon icon={AlertIcon} sx={{ ml: 2 }} />
              </Text>
            </FormControl.Caption>
          </FormControl>
        </Box>
      )}

      <ShadowTraffic fetcher={fetcher} corpus={corpus} />

      <ToggleForm
        fetcher={fetcher}
        name="indexing"
        value={corpus.indexing}
        caption="Should the crawlers process events? Use this to temporarily pause indexing."
        rpcMethod="SetCorpusIndexingState"
        sx={{ mt: 2 }}
      />

      <ToggleForm
        fetcher={fetcher}
        name="healing"
        value={corpus.healing}
        caption="Should this cluster heal?"
        rpcMethod="SetCorpusHealingState"
        sx={{ mt: 2 }}
      />
    </Box>
  );
}

function ChangeEpoch({ fetcher, corpora, corpus }) {
  const didChangeEpoch = fetcher.data && fetcher.data._rpcMethod === "ChangeEpoch";

  const allClusters = corpora
    .filter((c) => !c.corpus_name.includes("cache"))
    .toSorted((a, b) => b.epoch_id - a.epoch_id);
  let recommendedClusters = allClusters.filter(
    (c) => c.epoch_mode === corpus.epoch_mode || c.epoch_mode === corpora.epoch_mode
  );
  let otherClusters = allClusters.filter(
    (c) => c.epoch_mode !== corpus.epoch_mode && c.epoch_mode !== corpora.epoch_mode
  );
  const initial = allClusters.find((c) => c.epoch_id === corpus.epoch_id);
  const [cluster, setCluster] = useState(initial);
  const [epochId, setEpochId] = useState(initial?.epoch_id || "custom");
  const [epochMode, setEpochMode] = useState(initial?.epoch_mode || "custom");

  return (
    <Box>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="ChangeEpoch" />
        <input type="hidden" name="num_shards" value={cluster?.num_shards || "custom"} />
        <input type="hidden" name="cluster" value={corpus.cluster_name} />
        <input type="hidden" name="epoch_mode" value={epochMode} />
        <Box sx={{ display: "flex", flexDirection: "column" }}>
          <FormControl required sx={{ mb: 2 }}>
            <FormControl.Label>Epoch ID</FormControl.Label>
            <Select
              name="epoch_id"
              value={epochId}
              onChange={(e) => {
                setEpochId(e.target.value);
                const cluster = allClusters.find((c) => c.epoch_id.toString() === e.target.value);
                setCluster(cluster);
                setEpochMode(cluster?.epoch_mode || "custom");
              }}
            >
              <Select.Option key="ce-recommended" value="" disabled>
                Recommended epochs...
              </Select.Option>
              {recommendedClusters.map((c) => (
                <Select.Option key={`ce-${c.corpus_name}`} value={c.epoch_id}>
                  {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                </Select.Option>
              ))}
              <Select.Option key="ce-select" value="" disabled>
                Change of epoch mode...
              </Select.Option>
              {otherClusters.map((c) => (
                <Select.Option key={`ce-${c.corpus_name}`} value={c.epoch_id}>
                  {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                </Select.Option>
              ))}
              <Select.Option key="gl-other" value="" disabled>
                Good luck...
              </Select.Option>
              <Select.Option key="custom" value="custom">
                Use a custom epoch
              </Select.Option>
            </Select>
            <FormControl.Caption>Generally you want to pick the latest good serving epoch.</FormControl.Caption>
          </FormControl>

          <Box hidden={epochId !== "custom"}>
            <FormControl sx={{ mb: 2 }}>
              <FormControl.Label>Custom Epoch ID</FormControl.Label>
              <TextInput aria-label="Custom Epoch ID" name="custom_epoch_id" maxWidth={120} />
            </FormControl>
            <FormControl sx={{ mb: 2 }}>
              <FormControl.Label>Custom Epoch Mode</FormControl.Label>
              <Select name="custom_epoch_mode">
                {Object.keys(EpochMode).map((k) => (
                  <Select.Option key={k} value={EpochMode[k]}>
                    {EpochMode[k]}
                  </Select.Option>
                ))}
              </Select>
              <FormControl.Caption>
                Please manually verify the epoch mode is correct for the epoch ID you are using.
              </FormControl.Caption>
            </FormControl>
            <FormControl sx={{ mb: 2 }}>
              <FormControl.Label>Number of shards</FormControl.Label>
              <TextInput aria-label="Number of shards" name="custom_num_shards" maxWidth={120} />
              <FormControl.Caption>
                Please manually verify the number of shards is correct for the epoch ID you are using.
              </FormControl.Caption>
            </FormControl>
          </Box>

          <Box display="flex" alignItems="center">
            <Button type="submit">Change epoch</Button>
            {didChangeEpoch && (
              <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
                <Octicon icon={CheckIcon} /> Success! The cache cluster is transitioning epochs.
              </Text>
            )}
          </Box>
        </Box>
      </fetcher.Form>
    </Box>
  );
}

function HostsSection({ corpus, filter, setFilter }) {
  return (
    <Box sx={{ mb: 4 }}>
      <Pagehead sx={{ pb: 2, mb: 2 }}>Hosts</Pagehead>
      {corpus.snapshot ? (
        <ClusterHosts corpus={corpus} filter={filter} setFilter={setFilter} />
      ) : (
        <Text color="fg.subtle" fontSize={1}>
          Fetching hosts and shard assignments…
        </Text>
      )}
    </Box>
  );
}

function ClusterHosts({ corpus, filter, setFilter }) {
  const { snapshot, extraHosts, missingHosts } = corpus;
  const assignments = snapshot.host_assignments || [];

  const inner = (
    <Box sx={{ display: "flex", flexDirection: "column" }}>
      <Box sx={{ display: "flex", flexDirection: "column", mb: 2 }}>
        {missingHosts.length > 0 && (
          <Box sx={{ mb: 2 }}>
            <Text sx={{ fontWeight: "bold" }}>Sites API is missing {missingHosts.length} host(s)</Text>
            {missingHosts.map((host) => (
              <Box key={`missing-host-${host}`} sx={{ display: "flex" }}>
                <Text color="fg.text" fontSize={1} fontFamily="mono">
                  <Octicon icon={DiffRemovedIcon} sx={{ mr: 1, color: "danger.fg" }} />
                  {host}
                </Text>
              </Box>
            ))}
          </Box>
        )}

        {extraHosts.length > 0 && (
          <Box sx={{ mb: 2 }}>
            <Text sx={{ fontWeight: "bold" }}>{extraHosts.length} extra host(s) not participating in DSA</Text>
            {extraHosts.map((host) => (
              <Box key={`extra-host-${host}`} sx={{ display: "flex" }}>
                <Text color="fg.text" fontSize={1} fontFamily="mono">
                  <Octicon icon={DiffAddedIcon} sx={{ mr: 1, color: "success.fg" }} />
                  {host}
                </Text>
              </Box>
            ))}
          </Box>
        )}
      </Box>
      <TextInput
        leadingVisual={SearchIcon}
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        aria-label="Host filter"
        id="host-filter"
        placeholder="Filter by hostname, state, or shard id"
        sx={{ mb: 3, maxWidth: 300 }}
      />
      <Box sx={{ display: "flex", flexDirection: "column", mb: 2 }}>
        {assignments
          .filter((h) => {
            return (
              filter === "" ||
              h.hostname.includes(filter) ||
              h.assigned_shards.filter(
                (s) => s.state.toLowerCase().startsWith(filter) || s.shard_id.toString() === filter
              ).length > 0
            );
          })
          .sort(sortHosts)
          .map((host) => {
            const extra = (corpus.hosts || []).find((h) => h.hostname === host.hostname);
            return (
              <Box key={`host-${host.hostname}`} sx={{ display: "flex", mb: 2 }}>
                <Box sx={{ mr: 4, display: "flex", flexDirection: "column" }}>
                  <Text color="fg.text" fontSize={1} fontFamily="mono">
                    {host.hostname}
                  </Text>
                  <Text color="fg.subtle" fontSize={0}>
                    e{extra?.epoch_id} v{extra?.index_version}{" "}
                    <Truncate inline expandable title={extra?.binary_version} as="span" sx={{ maxWidth: 120 }}>
                      <Text fontFamily="mono">{extra?.binary_version}</Text>
                    </Truncate>
                  </Text>
                </Box>

                <Box sx={{ display: "flex", flexDirection: "column", ml: 2 }}>
                  {host.assigned_shards.map((shard) => {
                    const shardExtra = (extra?.shards || []).find((s) => s.shard_id === shard.shard_id);
                    return (
                      <Box key={`${host.hostname}-${shard.shard_id}`} sx={{ display: "flex" }}>
                        <Label variant={variantForState(shard.state)} sx={{ minWidth: 90, mb: 1 }}>
                          {shard.state}: {shard.shard_id}
                        </Label>
                        {shard.state === "SERVING" && shardExtra && (
                          <Text color="fg.subtle" fontSize={0} sx={{ ml: 2 }}>
                            {shardExtra.serving_offset} | {new Date(parseInt(shardExtra.serving_ts)).toLocaleString()}
                          </Text>
                        )}
                      </Box>
                    );
                  })}
                </Box>
              </Box>
            );
          })}
      </Box>
    </Box>
  );

  return (
    <>
      <Text color="fg.subtle" fontSize={1} display="block" sx={{ mb: 2 }}>
        <b>DSA algorithm:</b> v{snapshot.algorithm_version}
        <br />
        <b>Assignment offset:</b> {snapshot.offset}
        <Text sx={{ mx: 2 }} color="fg.subtle">
          ·
        </Text>
        <PrimerLink as={Link} to={`?offset=${parseInt(snapshot.offset, 10) - 1}`}>
          Previous
        </PrimerLink>
        <Text sx={{ mx: 2 }} color="fg.subtle">
          ·
        </Text>
        <PrimerLink as={Link} to={`?offset=${parseInt(snapshot.offset, 10) + 1}`} muted={snapshot.offset !== -1}>
          Next
        </PrimerLink>
        <Text sx={{ mx: 2 }} color="fg.subtle">
          ·
        </Text>
        <PrimerLink as={Link} to="" muted>
          Latest
        </PrimerLink>
        <br />
        <b>Assignment ts:</b> {snapshot.snapshot_time}
      </Text>
      {snapshot.failed ? (
        <Flash variant="danger">Failed to get shard assignments: {snapshot.error.statusText}</Flash>
      ) : (
        <Box>{inner}</Box>
      )}
    </>
  );
}

function ForceBootstrap({ corpus, fetcher }) {
  const didBackfill = fetcher.data && fetcher.data.rpcMethod === "BeginBackfillCorpus";
  return (
    <Box>
      <Text>Start an empty backfill. Be careful, this is probably not what you want to do.</Text>

      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="BeginBackfillCorpus"></input>
        <input type="hidden" name="bootstrap" value="true"></input>
        <Box display="flex" flexDirection="column" sx={{ my: 2 }}>
          <FormControl sx={{ mt: 2 }} required>
            <FormControl.Label>Number of shards</FormControl.Label>
            <TextInput
              aria-label="Number of shards"
              name="num_shards"
              defaultValue={corpus.num_shards}
              maxWidth={120}
            />
            <FormControl.Caption>
              Horizontal scaling factor. Also determines the number of partitions in the document topic.
            </FormControl.Caption>
          </FormControl>
          <Box display="flex" alignItems="center" sx={{ mt: 2 }}>
            <Button type="submit" variant="danger">
              Run a bootstrap backfill on {corpusDisplayName(corpus)}
            </Button>
            {didBackfill && (
              <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
                <Octicon icon={CheckIcon} /> Backfill started asynchronously.
              </Text>
            )}
          </Box>
        </Box>
      </fetcher.Form>
    </Box>
  );
}

function ColdStart({ corpus, fetcher }) {
  const didBackfill = fetcher.data && fetcher.data.rpcMethod === "BeginBackfillCorpus";
  return (
    <Box>
      <Text sx={{ color: "accent.fg" }}>
        <Octicon icon={InfoIcon} sx={{ mr: 2 }} />
        This cluster has never been backfilled. You must bootstrap with an empty backfill.
        <br />
      </Text>

      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="BeginBackfillCorpus"></input>
        <input type="hidden" name="bootstrap" value="true"></input>
        <Box display="flex" flexDirection="column" sx={{ my: 2 }}>
          <FormControl sx={{ mt: 2 }} required>
            <FormControl.Label>Number of shards</FormControl.Label>
            <TextInput
              aria-label="Number of shards"
              name="num_shards"
              defaultValue={corpus.num_shards}
              maxWidth={120}
            />
            <FormControl.Caption>
              Horizontal scaling factor. Also determines the number of partitions in the document topic.
            </FormControl.Caption>
          </FormControl>
          <Box display="flex" alignItems="center" sx={{ mt: 2 }}>
            <Button type="submit" variant="primary">
              Run a bootstrap backfill on {corpusDisplayName(corpus)}
            </Button>
            {didBackfill && (
              <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
                <Octicon icon={CheckIcon} /> Backfill started asynchronously.
              </Text>
            )}
          </Box>
        </Box>
      </fetcher.Form>
    </Box>
  );
}

function Backfill({ corpora, corpus, fetcher, deployEnv }) {
  const didBackfill = fetcher.data && fetcher.data.rpcMethod === "BeginBackfillCorpus";

  let allCacheClusters = corpora
    .filter((c) => c.corpus_name.includes("cache"))
    .toSorted((a, b) => b.epoch_id - a.epoch_id);
  let recommendedCacheClusters = allCacheClusters.filter((c) => c.epoch_mode === corpus.epoch_mode);
  let otherCacheClusters = allCacheClusters.filter((c) => c.epoch_mode !== corpus.epoch_mode);

  const recommendedCluster = recommendedCacheClusters.find((c) => c.corpus_name === corpus.cache_cluster);
  const [epochId, setEpochId] = useState(recommendedCluster?.epoch_id || "custom");
  const [epochMode, setEpochMode] = useState(recommendedCluster?.epoch_mode || EpochMode.Hybrid);

  const handleEpochIdChange = (event) => {
    const epochId = event.target.value;
    const c = allCacheClusters.find((c) => c.epoch_id.toString() === epochId);
    setEpochId(epochId);
    if (c) {
      setEpochMode(c.epoch_mode);
    }
  };

  const coldStart = !corpus.indexing && corpus.ingest_mode === "Legacy";
  if (coldStart) {
    return <ColdStart corpus={corpus} fetcher={fetcher} />;
  }

  return (
    <Box>
      <Box display="flex" flexDirection="column">
        <Text sx={{ color: "fg.subtle", mb: 2 }}>
          Rebuild the entire index by crawling all repositories. This can take several days.
        </Text>
        <fetcher.Form method="post">
          <input type="hidden" name="rpcMethod" value="BeginBackfillCorpus"></input>
          <Box display="flex" flexDirection="column">
            <>
              <FormControl required>
                <FormControl.Label>MST Epoch</FormControl.Label>
                <Select name="epoch_id" value={epochId} onChange={handleEpochIdChange}>
                  <Select.Option key="b-select" value="" disabled>
                    Recommended epochs...
                  </Select.Option>
                  {recommendedCacheClusters.map((c) => (
                    <Select.Option key={c.corpus_name} value={c.epoch_id}>
                      {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                    </Select.Option>
                  ))}
                  <Select.Option key="b-other" value="" disabled>
                    Epochs with other modes...
                  </Select.Option>
                  {otherCacheClusters.map((c) => (
                    <Select.Option key={`other-${c.corpus_name}`} value={c.epoch_id}>
                      {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                    </Select.Option>
                  ))}
                  <Select.Option key="gl-other" value="" disabled>
                    Good luck...
                  </Select.Option>
                  <Select.Option key="custom" value="custom">
                    Use a custom epoch
                  </Select.Option>
                </Select>
                <FormControl.Caption>Use this epoch to generate the MST that will drive backfill.</FormControl.Caption>
              </FormControl>

              <Box hidden={epochId !== "custom"}>
                <FormControl sx={{ mt: 2 }}>
                  <FormControl.Label>Custom MST source epoch</FormControl.Label>
                  <TextInput aria-label="Epoch ID" name="custom_epoch_id" maxWidth={120} />
                </FormControl>
              </Box>

              <FormControl required sx={{ mt: 2 }}>
                <FormControl.Label>Epoch Mode</FormControl.Label>
                <Select
                  name="epoch_mode"
                  value={epochMode}
                  onChange={(e) => {
                    setEpochMode(e.target.value);
                  }}
                >
                  {Object.keys(EpochMode).map((k) => (
                    <Select.Option key={k} value={EpochMode[k]}>
                      {EpochMode[k]}
                    </Select.Option>
                  ))}
                </Select>
                <FormControl.Caption>
                  Determines the set of repos to index and whether embeddings are to be indexed or not.
                </FormControl.Caption>
              </FormControl>
              <FormControl sx={{ mt: 2 }} required>
                <FormControl.Label>Number of shards</FormControl.Label>
                <TextInput
                  aria-label="Number of shards"
                  name="num_shards"
                  defaultValue={corpus.num_shards}
                  maxWidth={120}
                />
                <FormControl.Caption>
                  Horizontal scaling factor. Also determines the number of partitions in the document topic.
                </FormControl.Caption>
              </FormControl>
            </>
            <Box display="flex" alignItems="center" sx={{ mt: 2 }}>
              <Button
                type="submit"
                variant="danger"
                onClick={(e) => {
                  if (
                    !window.confirm(
                      `Are you sure you want to start a backfill? Did you remember to lock blackbird-mw in ${deployEnv}?`
                    )
                  ) {
                    e.preventDefault();
                  }
                }}
              >
                Backfill {corpus.cluster_name}
              </Button>
              {didBackfill && (
                <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
                  <Octicon icon={CheckIcon} /> Backfill started asynchronously.
                </Text>
              )}
            </Box>
          </Box>
        </fetcher.Form>

        <Text sx={{ color: "accent.fg", mt: 3 }}>
          <Octicon icon={InfoIcon} sx={{ mr: 1 }} />
          Before beginning a backfill, make sure to <code>.lock blackbird-mw in {deployEnv}</code>
        </Text>
      </Box>
    </Box>
  );
}

function Pin({ corpus, fetcher }) {
  let isPinned = false;
  let isPinning = false;
  if (corpus.pinned_serving_ts && corpus.serving_ts <= corpus.pinned_serving_ts) {
    isPinned = true;
  } else if (corpus.pinned_serving_ts) {
    isPinning = true;
  }

  const now = new Date();

  return (
    <Box>
      <Box>
        <Text sx={{ color: "fg.subtle" }}>Pin this corpus to a specific serving timestamp.</Text>
      </Box>
      {isPinning ? (
        <Box>
          <Flash variant="warning" sx={{ my: 2 }}>
            <Octicon icon={ClockIcon} />
            Pinning now. This can take up to 30 minutes.
          </Flash>
          <Text color="fg.subtle" fontSize={1} display="block" sx={{ mt: 2 }}>
            <b>pinned_ts:</b> {corpus.pinned_serving_ts}
            <br />
            <b>current serving_ts:</b> {corpus.serving_ts}
          </Text>
        </Box>
      ) : isPinned ? (
        <Box>
          <Flash sx={{ my: 2 }}>
            <Octicon icon={PinIcon} />
            This cluster is pinned. It can serve queries but will not perform any indexing.
          </Flash>
          <Text color="fg.subtle" fontSize={1} display="block" sx={{ mt: 2 }}>
            <b>pinned_ts:</b> {corpus.pinned_serving_ts}
            <br />
            <b>current serving_ts:</b> {corpus.serving_ts}
          </Text>

          <fetcher.Form method="post">
            <input type="hidden" name="rpcMethod" value="UnpinCorpus"></input>
            <Box display="flex" flexDirection="column">
              <Box display="flex" alignItems="center" sx={{ mt: 2 }}>
                <Button type="submit">Unpin {corpus.cluster_name}</Button>
              </Box>
            </Box>
          </fetcher.Form>
        </Box>
      ) : (
        <Box>
          <Text color="fg.subtle" fontSize={1} display="block" sx={{ mt: 2 }}>
            <b>current serving_ts:</b> {corpus.serving_ts}
          </Text>
          <fetcher.Form method="post">
            <input type="hidden" name="rpcMethod" value="PinCorpus"></input>
            <Box display="flex" flexDirection="column">
              <FormControl required sx={{ mt: 2 }}>
                <FormControl.Label>Serving Timestamp</FormControl.Label>
                <TextInput
                  aria-label="Serving Timestamp"
                  name="serving_ts"
                  minWidth={350}
                  placeholder={`${now.getTime()} or ${now.toISOString()}`}
                />
              </FormControl>
              <Text color="fg.subtle" fontSize={1} display="block" sx={{ mt: 2 }}>
                The timestamp can be specified as an RFC3339 formatted date or as milliseconds since the Unix epoch.
                <br />
                Note: It can take up to 30 minutes to pin the cluster to a prior state.
              </Text>
              <Box display="flex" alignItems="center" sx={{ mt: 2 }}>
                <Button
                  variant="danger"
                  type="submit"
                  onClick={(e) => {
                    if (
                      !window.confirm(
                        `${corpus.serving ? "This cluster is actively serving. " : ""}Are you sure you want to pin?`
                      )
                    ) {
                      e.preventDefault();
                    }
                  }}
                >
                  Pin
                </Button>
              </Box>
            </Box>
          </fetcher.Form>
        </Box>
      )}
    </Box>
  );
}

// Can a corpus branch to the given epoch mode?
function canBranch(corpus, toMode) {
  if (corpus.epoch_mode === EpochMode.Hybrid) {
    // hybrid can branch to any mode
    return true;
  } else {
    return toMode === corpus.epoch_mode;
  }
}

const validateBranchTimestamp = (ts) => {
  if (ts === "" || (!Number.isSafeInteger(Number(ts)) && isNaN(new Date(ts).getTime()))) {
    return "error";
  }
  return "success";
};

function BranchValidationMessage({ validationResult }) {
  if (validationResult === null || validationResult === "success") return null;
  return (
    <FormControl.Validation variant="error">
      Branch timestamp must be an RFC3339 date or milliseconds since the epoch.
    </FormControl.Validation>
  );
}

function BranchEpoch({ corpus, corpora, fetcher, deployEnv }) {
  const clusters = corpora.filter((c) => !c.corpus_name.includes("cache")).toSorted((a, b) => b.epoch_id - a.epoch_id);
  let recommendedClusters = clusters.filter((c) => c.epoch_mode === corpus.epoch_mode);
  let otherClusters = clusters.filter((c) => c.epoch_mode !== corpus.epoch_mode);

  const [selectedCorpus, setSelectedCorpus] = useState(recommendedClusters[0] || clusters[0]);
  const [epochMode, setEpochMode] = useState(selectedCorpus.epoch_mode || EpochMode.Hybrid);
  const [branchTimestamp, setBranchTimestamp] = useState("");
  const [validationResult, setValidationResult] = useState(null);

  const handleClusterChange = (event) => {
    const corpus = event.target.value;
    const selectedCorpus = corpora.find((c) => c.corpus_name === corpus);
    setSelectedCorpus(selectedCorpus);
    if (selectCorpus) {
      setEpochMode(selectedCorpus.epoch_mode);
    }
  };

  const handleBranchTimestampChange = (event) => {
    setBranchTimestamp(event.target.value);
    setValidationResult(validateBranchTimestamp(event.target.value));
  };

  return (
    <Box>
      <Box sx={{ display: "flex", flexDirection: "column" }}>
        <Text sx={{ color: "fg.subtle" }}>
          Branch off an existing epoch to quickly roll out changes to this cluster. This can take several hours.
        </Text>
        <fetcher.Form method="post">
          <input type="hidden" name="rpcMethod" value="BranchEpoch" />
          <input type="hidden" name="source_epoch" value={selectedCorpus.epoch_id} />
          <input type="hidden" name="num_shards" value={selectedCorpus.num_shards} />
          <input type="hidden" name="epoch_mode" value={selectedCorpus.epoch_mode} />
          <Box display="flex" flexDirection="column">
            <Box sx={{ display: "flex", alignItems: "center" }}>
              <FormControl sx={{ mt: 2 }} required>
                <FormControl.Label>Source Epoch</FormControl.Label>
                <Select name="source_corpus" value={selectedCorpus.corpus_name} onChange={handleClusterChange}>
                  <Select.Option key="be-select" value="" disabled>
                    Recommended epochs...
                  </Select.Option>
                  {recommendedClusters.map((c) => (
                    <Select.Option key={c.corpus_name} value={c.corpus_name}>
                      {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                    </Select.Option>
                  ))}
                  <Select.Option key="be-other" value="" disabled>
                    Epochs with other modes...
                  </Select.Option>
                  {otherClusters.map((c) => (
                    <Select.Option key={`be-other-${c.corpus_name}`} value={c.corpus_name}>
                      {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                    </Select.Option>
                  ))}
                </Select>
                <FormControl.Caption>Branch from this epoch.</FormControl.Caption>
              </FormControl>
              <Text sx={{ ml: 2, mt: 2 }} color="fg.subtle" fontSize={1}>
                <b>serving_ts:</b> {selectedCorpus.serving_ts}
              </Text>
            </Box>
            <FormControl required sx={{ mt: 2 }}>
              <FormControl.Label>Epoch Mode</FormControl.Label>
              <Select
                name="epoch_mode"
                value={epochMode}
                onChange={(e) => {
                  setEpochMode(e.target.value);
                }}
              >
                {Object.keys(EpochMode)
                  .map((k) => EpochMode[k])
                  .filter((m) => canBranch(selectedCorpus, m))
                  .map((m) => (
                    <Select.Option key={`branch-${m}`} value={m}>
                      {m}
                    </Select.Option>
                  ))}
              </Select>
              <FormControl.Caption>
                Determines the set of repos to index and whether embeddings are to be indexed or not.
              </FormControl.Caption>
            </FormControl>
            <FormControl required sx={{ mt: 2 }}>
              <FormControl.Label>Branch Timestamp</FormControl.Label>
              <TextInput
                aria-label="Branch Timestamp"
                name="branch_ts"
                minWidth={350}
                placeholder={selectedCorpus.serving_ts}
                onChange={handleBranchTimestampChange}
                value={branchTimestamp}
                validationStatus={validationResult}
              />
              <BranchValidationMessage validationResult={validationResult} />
              <FormControl.Caption>
                Branch at this point in time. Can be specified as an RFC3339 formatted date or as milliseconds since the
                Unix epoch.
              </FormControl.Caption>
            </FormControl>
            <Box display="flex" alignItems="center" sx={{ mt: 2 }}>
              <Button
                variant="danger"
                type="submit"
                onClick={(e) => {
                  if (validationResult !== "success") {
                    document.getElementsByName("branch_ts")[0].select();
                    e.preventDefault();
                  } else if (
                    !window.confirm(
                      `Are you sure you want to create a new branch on ${corpus.corpus_name}(${corpus.cluster_name})? Did you remember to lock blackbird-mw in ${deployEnv}?`
                    )
                  ) {
                    e.preventDefault();
                  }
                }}
              >
                Create branch
              </Button>
            </Box>
          </Box>
        </fetcher.Form>

        <Text sx={{ color: "accent.fg", mt: 3 }}>
          <Octicon icon={InfoIcon} sx={{ mr: 1 }} />
          Before branching, make sure to <code>.lock blackbird-mw in {deployEnv}</code>
        </Text>
      </Box>
    </Box>
  );
}

function SetCacheCluster({ corpus, corpora, fetcher }) {
  const [corpusCacheCluster, setCorpusCacheCluster] = useState(corpus.cache_cluster);

  let allCacheClusters = corpora.filter((c) => c.corpus_name.includes("cache"));
  let cacheClusters = allCacheClusters.filter(
    (c) => c.epoch_mode === corpus.epoch_mode || c.epoch_mode === EpochMode.Hybrid
  );
  let otherClusters = allCacheClusters.filter(
    (c) => c.epoch_mode !== corpus.epoch_mode && c.epoch_mode !== EpochMode.Hybrid
  );
  return (
    <Box sx={{ mt: 2, display: "flex", alignItems: "center", justifyContent: "space-between" }}>
      <Box flexShrink={4}>
        <Text fontWeight="bold">Cache Cluster</Text>
        <Text sx={{ color: "fg.subtle", fontSize: 1, maxWidth: 580, display: "block" }}>
          Reduces the load on spokes, extracts symbols, and fetches embeddings during crawling.
        </Text>
      </Box>
      <Box>
        <fetcher.Form method="post">
          <input type="hidden" name="rpcMethod" value="SetCorpusCacheCluster"></input>
          <Box display="flex">
            <FormControl required>
              <FormControl.Label visuallyHidden>Cache Cluster</FormControl.Label>
              <Select
                name="cache_cluster"
                value={corpusCacheCluster}
                onChange={(e) => setCorpusCacheCluster(e.target.value)}
              >
                <Select.Option key="select" value="" disabled>
                  Select a cluster...
                </Select.Option>
                {cacheClusters.map((c) => (
                  <Select.Option key={c.corpus_name} value={c.corpus_name}>
                    {c.corpus_name} ({c.epoch_mode})
                  </Select.Option>
                ))}
                <Select.Option key="other" value="" disabled>
                  Clusters with incompatible modes...
                </Select.Option>
                {otherClusters.map((c) => (
                  <Select.Option key={`other-${c.corpus_name}`} value={c.corpus_name}>
                    {c.corpus_name} ({c.epoch_mode})
                  </Select.Option>
                ))}
              </Select>
            </FormControl>
            <Button type="submit" disabled={corpusCacheCluster === corpus.cache_cluster} sx={{ ml: 2 }}>
              Save
            </Button>
          </Box>
        </fetcher.Form>
      </Box>
    </Box>
  );
}

function ColorBar({ snapshot, isCacheCluster }) {
  return (
    <Box sx={{ display: "flex", border: "0px solid", borderRadius: 1, borderColor: "border.muted", minHeight: 79 }}>
      {snapshot ? (
        snapshot.failed ? (
          <Flash variant="danger" sx={{ display: "flex", flex: 1 }}>
            Failed to get shard assignments: <br />
            {snapshot.error.statusText}
          </Flash>
        ) : (
          <PrettyBoxes snapshot={snapshot} isCacheCluster={isCacheCluster} />
        )
      ) : (
        <PrettyBoxesBlankslate />
      )}
    </Box>
  );
}

function PrettyBoxesBlankslate() {
  let items = [...Array(32).keys()].map((i) => {
    return (
      <Box key={`bs-${i}`} flex={1} height={79} border="1px solid" borderRadius={1} borderColor="border.muted"></Box>
    );
  });
  return <>{items}</>;
}

function PrettyBoxes({ snapshot, isCacheCluster }) {
  const m = new Map();
  const shardSet = new Set();
  (snapshot.host_assignments || []).forEach((host) => {
    (host.assigned_shards || []).forEach((shard, i) => {
      const isServing = shard.state === "SERVING";
      let isPrimary = isServing && i === 0;
      if (isCacheCluster) {
        if (!shardSet.has(shard.shard_id) && isServing) {
          isPrimary = true;
          shardSet.add(shard.shard_id);
        } else {
          isPrimary = false;
        }
      }

      const key = shard.shard_id;
      const v = m.get(key) || [];
      v.push({
        hostname: host.hostname,
        state: shard.state,
        isServing: isServing,
        isPrimary: isPrimary,
      });
      m.set(key, v);
    });
  });
  let items = Array.from(m)
    .sort((a, b) => {
      return a[0] < b[0] ? -1 : 1;
    })
    .map(([shard_id, hosts]) => {
      return (
        <Box key={`cb-${shard_id}`} flex={1} display="flex" flexDirection="column">
          <Box
            sx={{
              display: "flex",
              justifyContent: "center",
              border: "1px solid",
              borderRadius: 1,
              borderColor: "border.muted",
              borderBottom: 0,
              borderBottomLeftRadius: 0,
              borderBottomRightRadius: 0,
            }}
          >
            <Text fontSize="6px" color="fg.muted" textAlign="center" sx={{ display: ["none", "inline"] }}>
              {shard_id}
            </Text>
          </Box>
          {hosts
            .sort((a, b) => {
              // TODO: Use sequenceIdx here
              if (a.isServing && !b.isServing) {
                return -1;
              } else if (!a.isServing && b.isServing) {
                return 1;
              } else if (a.isPrimary) {
                return -1;
              } else if (b.isPrimary) {
                return 1;
              }
              return 0;
            })
            .map((host, i) => {
              let primary = host.isPrimary ? " (primary)" : "";
              return (
                <Tooltip
                  key={`cb-${host.hostname}`}
                  aria-label={`${host.hostname}\n${host.state}: ${shard_id}${primary}`}
                >
                  <Box
                    minHeight={15}
                    border="1px solid"
                    borderRadius={1}
                    borderColor="border.muted"
                    sx={{ bg: bgForState(host.state, host.isPrimary || !host.isServing) }}
                  />
                </Tooltip>
              );
            })}
        </Box>
      );
    });

  return <>{items}</>;
}

function IndexRepoList({ corpora, fetcher }) {
  const [repoList, setRepoList] = useState([]);
  const [textAreaValue, setTextareaValue] = useState("");

  const handleTextareaChange = (e) => {
    const value = e.target.value;
    // Allow only numeric input
    if (!/^[\d\n]*$/.test(value)) {
      return;
    }

    setTextareaValue(value);
    const repoArray = value
      .split("\n")
      .filter((line) => line.trim() !== "")
      .map(Number);
    setRepoList(repoArray);
  };

  return (
    <Box>
      <Pagehead sx={{ pb: 2, mb: 2 }}>Index repos</Pagehead>
      <Box>
        <Text color="fg.subtle" fontSize={1} display="block">
          Force index a list of repo ids.
        </Text>
      </Box>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="IndexRepoList" />
        <input type="hidden" name="repo_ids" value={JSON.stringify(repoList)} />
        <Box display="flex">
          <FormControl required sx={{ mt: 2 }}>
            <FormControl.Label>Enter one repo id per line</FormControl.Label>
            <Textarea
              name="repoListDisplay"
              sx={{ width: 500 }}
              onChange={handleTextareaChange}
              value={textAreaValue}
            />
          </FormControl>
        </Box>
        <Box display="flex" alignItems="center" sx={{ mt: 2 }}>
          <Button
            variant="danger"
            type="submit"
            onClick={(e) => {
              if (repoList.length === 0) {
                window.alert("Please enter at least one repo");
                e.preventDefault();
              }
            }}
          >
            Index Repos
          </Button>
        </Box>
      </fetcher.Form>
    </Box>
  );
}

const dsaStates = {
  serving: "success",
  backfilling: "accent",
  compacting: "attention",
  downloading: "done",
  waiting: "danger",
  warming_up: "sponsors",
  unknown: "nuetral",
};

function bgForState(state, emphasis) {
  let color = dsaStates[state.toLowerCase()];
  if (!color) {
    return "neutral.muted";
  }
  return `${color}.${emphasis ? "emphasis" : "muted"}`;
}

function variantForState(state) {
  let variant = dsaStates[(state || "").toLowerCase()];
  if (!variant) {
    variant = "danger";
  }
  return variant;
}

function sortHosts(a, b) {
  if (a.assigned_shards.length === 0 || b.assigned_shards.length === 0) {
    return 1;
  }
  if (a.assigned_shards[0].shard_id < b.assigned_shards[0].shard_id) {
    return -1;
  } else if (a.assigned_shards[0].shard_id === b.assigned_shards[0].shard_id) {
    if (a.assigned_shards[0].state === "SERVING") {
      return -1;
    }
  }
  return 1;
}

function setIf(data, formData, key) {
  if (formData.get(key)) {
    data[key] = formData.get(key);
  }
}

function setIfArray(data, formData, key) {
  if (formData.get(key)) {
    data[key] = JSON.parse(formData.get(key));
  }
}

function setIfBool(data, formData, key) {
  if (formData.get(key)) {
    data[key] = !!formData.get(key);
  }
}
