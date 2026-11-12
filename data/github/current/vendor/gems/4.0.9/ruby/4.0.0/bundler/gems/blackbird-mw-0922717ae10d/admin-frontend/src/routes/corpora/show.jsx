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
  Flash,
  Textarea,
  Stack,
  PageHeader,
  IconButton,
} from "@primer/react";
import { DataTable, InlineMessage, Table, UnderlinePanels } from "@primer/react/experimental";
import { useFetcher, Link, useOutletContext, useParams } from "react-router-dom";
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
  GitBranchIcon,
  RepoPushIcon,
  StackIcon,
  ZapIcon,
  ServerIcon,
  CopyIcon,
  LinkExternalIcon,
} from "@primer/octicons-react";
import { corpusDisplayName, titleize } from "../../components/corpus";
import { BuildDiffLink } from ".";
import { getSplunkLink } from "../../components/splunk";

export async function action({ request, params }) {
  let formData = await request.formData();
  let data = { corpus: params.name };

  if (formData.get("serving")) {
    data.serving = formData.get("serving") === "true";
  } else if (formData.get("instant_serving")) {
    data.instant_serving = formData.get("instant_serving") === "true";
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
  } else if (formData.get("num_shards")) {
    data["num_shards"] = formData.get("num_shards");
  }
  setIf(data, formData, "mst_cache_cluster");

  setIfBool(data, formData, "bootstrap");
  setIfBool(data, formData, "force");
  setIf(data, formData, "cluster");
  setIf(data, formData, "percent");
  setIf(data, formData, "healing_rate");
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
  const { corpora, corpus, deployEnv, epochModes, availabilityZone, region, vmSize, provisionedHosts } =
    useOutletContext();
  const [filter, setFilter] = useState("");
  const fetcher = useFetcher();
  const params = useParams();

  let numServingCorpora = 0;
  for (const c of corpora) {
    if (c.serving) {
      numServingCorpora++;
    }
  }
  const anotherCorpusServing = numServingCorpora > 1;
  const isCacheCluster = corpus.cluster_name.includes("cache");
  const maxRepos = parseInt(corpus.max_repos_indexed).toLocaleString();

  const columns = [
    { header: "Property", field: "key", rowHeader: true, width: "growCollapse", minWidth: "100px" },
    { header: "Value", field: "value", rowHeader: false, width: "growCollapse", minWidth: "110px" },
  ];
  const data = [
    { key: "Epoch", value: `e${corpus.epoch_id}` },
    { key: "Epoch mode", value: corpus.epoch_mode },
    { key: "Index version", value: `v${corpus.index_version}` },
    { key: "Num hosts", value: provisionedHosts },
    { key: "Num shards", value: corpus.num_shards },
    { key: "Repos indexed (est.)", value: maxRepos },
    { key: "Build date", value: BuildDiffLink({ corpus })},
    { key: "Availability zone", value: availabilityZone },
    { key: "Region", value: region },
    { key: "VM size", value: vmSize },
    { key: "DSA hosts", value: corpus.snapshot?.host_assignments?.length ?? 0 },
    { key: "DSA algorithm", value: corpus.snapshot && `v${corpus.snapshot.algorithm_version}` },
    { key: "DSA offset", value: corpus.snapshot?.offset },
  ];

  return (
    <Box flexGrow={1}>
      <Box display="flex" flexDirection="column">
        <ColorBar corpus={corpus} isCacheCluster={isCacheCluster} />
        {isCacheCluster ? (
          <Box display="flex" flexDirection="column">
            <PageHeader role="banner" aria-label="Title">
              <PageHeader.TitleArea>
                <PageHeader.Title>{corpus.corpus_name}</PageHeader.Title>
              </PageHeader.TitleArea>
            </PageHeader>
            <Stack direction="horizontal" justify="space-between">
              <Stack.Item grow>
                <Stack gap="condensed" direction="horizontal" align="center" justify="space-between">
                  {!corpus.active_epoch && (
                    <Text sx={{ fontSize: 1, color: "danger.fg" }}>
                      <Octicon icon={CloudOfflineIcon} /> Epoch {corpus.epoch_id} is no longer active — load a newer one
                    </Text>
                  )}
                  <Text sx={{ fontSize: 1, color: "fg.subtle" }}>{corpus.epoch_description}</Text>
                  <Text color="fg.subtle" fontSize={1}>
                    <PrimerLink href={getSplunkLink(params.stamp, `cluster=${corpus.cluster_name}`)} target="_blank">
                      Splunk <Octicon icon={LinkExternalIcon} />
                    </PrimerLink>
                  </Text>
                </Stack>
                <ChangeEpoch fetcher={fetcher} corpora={corpora} corpus={corpus} epochModes={epochModes} />
              </Stack.Item>

              <Stack>
                <Table.Container>
                  <DataTable data={data} columns={columns} />
                </Table.Container>
              </Stack>
            </Stack>

            <HostsSection corpus={corpus} filter={filter} setFilter={setFilter} />
          </Box>
        ) : (
          <Box sx={{ display: "flex", flexDirection: "column" }}>
            <PageHeader role="banner" aria-label="Title">
              <PageHeader.TitleArea>
                <PageHeader.Title>{corpusDisplayName(corpus)}</PageHeader.Title>
              </PageHeader.TitleArea>
            </PageHeader>

            <Stack direction="horizontal" justify="space-between">
              <Stack.Item grow>
                <Stack gap="condensed">
                  <Stack gap="condensed" direction="horizontal" align="center" justify="space-between">
                    <EpochDescription fetcher={fetcher} corpus={corpus} />
                    <Text color="fg.subtle" fontSize={1}>
                      <PrimerLink href={getSplunkLink(params.stamp, `cluster=${corpus.cluster_name}`)} target="_blank">
                        Splunk <Octicon icon={LinkExternalIcon} />
                      </PrimerLink>
                    </Text>
                  </Stack>
                  <SetCacheCluster corpus={corpus} corpora={corpora} fetcher={fetcher} />
                  <ServingToggle fetcher={fetcher} corpus={corpus} anotherCorpusServing={anotherCorpusServing} />
                  <ToggleForm
                    fetcher={fetcher}
                    name="instant_serving"
                    value={corpus.instant_serving}
                    caption="Indexer hosts will serve data from the instant index."
                    rpcMethod="SetCorpusInstantServingState"
                    sx={{ mt: 2 }}
                  />
                  <ToggleForm
                    fetcher={fetcher}
                    name="indexing"
                    value={corpus.indexing}
                    caption="Disable to temporarily pause ingest."
                    rpcMethod="SetCorpusIndexingState"
                    sx={{ mt: 2 }}
                  />
                  <ToggleForm
                    fetcher={fetcher}
                    name="healing"
                    value={corpus.healing}
                    caption="Run the metadata healing probers."
                    rpcMethod="SetCorpusHealingState"
                    sx={{ mt: 2 }}
                  />
                  <ShadowTraffic fetcher={fetcher} corpus={corpus} />
                  <HealingRate fetcher={fetcher} corpus={corpus} />
                </Stack>
              </Stack.Item>
              <Stack>
                <Table.Container>
                  <DataTable data={data} columns={columns} />
                </Table.Container>
              </Stack>
            </Stack>

            {corpus.epoch_features_external_content ? (
              <ExternalCluster
                corpus={corpus}
                corpora={corpora}
                fetcher={fetcher}
                deployEnv={deployEnv}
                epochModes={epochModes}
              />
            ) : (
              <GitHubCluster
                corpus={corpus}
                corpora={corpora}
                fetcher={fetcher}
                deployEnv={deployEnv}
                epochModes={epochModes}
              />
            )}

            <HostsSection corpus={corpus} filter={filter} setFilter={setFilter} />
          </Box>
        )}
      </Box>
    </Box>
  );
}

function GitHubCluster({ corpus, corpora, fetcher, deployEnv, epochModes }) {
  return (
    <Box sx={{ mt: 4, px: 2, pb: 2, backgroundColor: "canvas.subtle", borderRadius: 2 }}>
      <UnderlinePanels aria-label="Select a tab">
        <UnderlinePanels.Tab icon={GitBranchIcon}>Epoch Branch</UnderlinePanels.Tab>
        <UnderlinePanels.Tab icon={StackIcon}>Backfill</UnderlinePanels.Tab>
        <UnderlinePanels.Tab icon={PinIcon}>Pin</UnderlinePanels.Tab>
        <UnderlinePanels.Tab icon={ZapIcon}>Force Bootstrap</UnderlinePanels.Tab>
        <UnderlinePanels.Tab icon={RepoPushIcon}>Index Repos</UnderlinePanels.Tab>
        <UnderlinePanels.Panel>
          <BranchEpoch
            corpus={corpus}
            corpora={corpora}
            fetcher={fetcher}
            deployEnv={deployEnv}
            epochModes={epochModes}
          />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel>
          <Backfill corpora={corpora} corpus={corpus} fetcher={fetcher} deployEnv={deployEnv} epochModes={epochModes} />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel>
          <Pin corpus={corpus} fetcher={fetcher} />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel>
          <ForceBootstrap
            corpus={corpus}
            corpora={corpora}
            fetcher={fetcher}
            epochModes={epochModes}
            message="Used to bootstrap blackbird in new proxima stamps."
            deployEnv={deployEnv}
          />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel>
          <IndexRepoList corpora={corpora} fetcher={fetcher} />
        </UnderlinePanels.Panel>
      </UnderlinePanels>
    </Box>
  );
}

function ExternalCluster({ corpus, corpora, fetcher, deployEnv, epochModes }) {
  return (
    <Box sx={{ mt: 4, px: 2, pb: 2, backgroundColor: "canvas.subtle", borderRadius: 2 }}>
      <UnderlinePanels aria-label="Select a tab">
        <UnderlinePanels.Tab icon={GitBranchIcon}>Epoch Branch</UnderlinePanels.Tab>
        <UnderlinePanels.Tab icon={StackIcon}>Backfill</UnderlinePanels.Tab>
        <UnderlinePanels.Tab icon={ZapIcon}>Force Bootstrap</UnderlinePanels.Tab>
        <UnderlinePanels.Panel>
          <BranchEpoch
            corpus={corpus}
            corpora={corpora}
            fetcher={fetcher}
            deployEnv={deployEnv}
            epochModes={epochModes}
          />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel>
          <Backfill corpora={corpora} corpus={corpus} fetcher={fetcher} deployEnv={deployEnv} epochModes={epochModes} />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel>
          <ForceBootstrap
            corpus={corpus}
            corpora={corpora}
            fetcher={fetcher}
            epochModes={epochModes}
            deployEnv={deployEnv}
          />
        </UnderlinePanels.Panel>
      </UnderlinePanels>
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
          <Box sx={{ display: "flex", alignItems: "center" }}>
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
        <FormControl required>
          <FormControl.Label>Shadow Traffic %</FormControl.Label>
          <FormControl.Caption>
            Percent of traffic to send to {corpus.cluster_name} when it's not selected as the primary. Specified as 0.0
            to 1.0.
          </FormControl.Caption>
          <TextInput
            aria-label="Percent"
            name="percent"
            size="small"
            placeholder={0.0}
            defaultValue={percent}
            trailingAction={
              <Button
                type="submit"
                size="small"
                variant="invisible"
                sx={{ mr: 1 }}
                onClick={(e) => setPercent(e.target.value)}
              >
                Save
              </Button>
            }
          />
          <FormControl.Validation>
            {didSet && (
              <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
                <Octicon icon={CheckIcon} /> Success! Shadow traffic updated.
              </Text>
            )}
          </FormControl.Validation>
        </FormControl>
      </fetcher.Form>
    </Box>
  );
}

function HealingRate({ fetcher, corpus }) {
  const [rate, setRate] = useState(corpus.healing_rate || 0.0);
  const didSet = fetcher.data?._rpcMethod === "SetCorpusHealingRate";

  return (
    <Box sx={{ mt: 2 }}>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="SetCorpusHealingRate"></input>
        <input type="hidden" name="corpus" value={corpus.corpus_name}></input>
        <FormControl required>
          <FormControl.Label>Document Healing Rate</FormControl.Label>
          <FormControl.Caption>
            Rate in docs/sec to scan and repair documents by recomputing language, symbols, embeddings.
          </FormControl.Caption>
          <TextInput
            aria-label="Healing Rate"
            name="healing_rate"
            size="small"
            placeholder={0.0}
            defaultValue={rate}
            trailingAction={
              <Button
                type="submit"
                size="small"
                variant="invisible"
                sx={{ mr: 1 }}
                onClick={(e) => setRate(e.target.value)}
              >
                Save
              </Button>
            }
          />
          <FormControl.Validation>
            {didSet && (
              <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
                <Octicon icon={CheckIcon} /> Success! Healing rate updated.
              </Text>
            )}
          </FormControl.Validation>
        </FormControl>
      </fetcher.Form>
    </Box>
  );
}

function ToggleForm({ fetcher, name, value, caption, rpcMethod, disabled = false, sx, children }) {
  const [checked, setChecked] = useState(value);
  const onClick = () => setChecked(!checked);
  const capitalName = titleize(name);

  return (
    <Stack gap="none">
      <Stack direction="horizontal" align="center" justify="space-between">
        <div id={`is${capitalName}Id`}>{capitalName}</div>
        <fetcher.Form method="post">
          <input type="hidden" name={name} value={checked} />
          <input type="hidden" name="rpcMethod" value={rpcMethod} />
          <ToggleSwitch
            disabled={disabled}
            pl={2}
            size="small"
            checked={checked}
            aria-labelledby={`is${capitalName}Label`}
            onClick={onClick}
          />
        </fetcher.Form>
      </Stack>
      <Stack>
        {caption && (
          <Text color="fg.subtle" fontSize={0} id={`is${capitalName}Caption`} display="block" sx={{ mr: 1 }}>
            {caption}
          </Text>
        )}
        {children}
      </Stack>
    </Stack>
  );
}

function ServingToggle({ fetcher, corpus, anotherCorpusServing }) {
  const [isServing, setIsServing] = useState(corpus.serving);
  const [force, setForce] = useState(false);
  const disabled = corpus.serving && !anotherCorpusServing && !force;

  return (
    <>
      <fetcher.Form method="post">
        <input type="hidden" name="serving" value={isServing} />
        <input type="hidden" name="force" value={force} />
        <input type="hidden" name="rpcMethod" value="SetCorpusQueryState" />
        <Stack gap="none">
          <Stack direction="horizontal" align="center" justify="space-between">
            <div id="isServingLabel-toggle-label">Serving</div>
            <ToggleSwitch
              pl={2}
              size="small"
              disabled={disabled}
              checked={isServing}
              aria-labelledby="isServingLabel-toggle-label"
              onClick={() => setIsServing(!isServing)}
            />
          </Stack>
          {!corpus.serving && corpus.ingest_mode !== "Incremental" ? (
            <Text fontSize={0} sx={{ color: "attention.emphasis" }}>
              <Octicon icon={AlertIcon} /> Usually best to wait until the backfill is complete.
            </Text>
          ) : (
            <Text color="fg.subtle" fontSize={0}>
              When enabled, the cluster <i>can</i> serve user queries (based on auto cluster selection).
            </Text>
          )}
        </Stack>
      </fetcher.Form>
      {corpus.serving && !anotherCorpusServing && (
        <Box sx={{ display: "flex", alignItems: "center", pt: 1 }}>
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
    </>
  );
}

function ChangeEpoch({ fetcher, corpora, corpus, epochModes }) {
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
    <Box
      sx={{
        mt: 2,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
      }}
    >
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="ChangeEpoch" />
        <input type="hidden" name="num_shards" value={cluster?.num_shards || "custom"} />
        <input type="hidden" name="cluster" value={corpus.cluster_name} />
        <input type="hidden" name="epoch_mode" value={epochMode} />
        <Box sx={{ display: "flex", flexDirection: "column" }}>
          <FormControl required sx={{ mb: 2 }}>
            <FormControl.Label>Epoch</FormControl.Label>
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
              <TextInput aria-label="Custom Epoch ID" name="custom_epoch_id" value={corpus.epoch_id} maxWidth={120} />
            </FormControl>
            <FormControl sx={{ mb: 2 }}>
              <FormControl.Label>Custom Epoch Mode</FormControl.Label>
              <Select name="custom_epoch_mode">
                {epochModes.map((mode) => (
                  <Select.Option key={mode} value={mode}>
                    {mode}
                  </Select.Option>
                ))}
              </Select>
              <FormControl.Caption>
                Please manually verify the epoch mode is correct for the epoch ID you are using.
              </FormControl.Caption>
            </FormControl>
            <FormControl sx={{ mb: 2 }}>
              <FormControl.Label>Number of shards</FormControl.Label>
              <TextInput
                aria-label="Number of shards"
                name="custom_num_shards"
                value={corpus.num_shards}
                maxWidth={120}
              />
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
  const { snapshot } = corpus;
  const assignments = snapshot?.host_assignments || [];
  let missingHosts = corpus.missingHosts || [];
  let extraHosts = corpus.extraHosts || [];

  let columns = [
    { header: "", field: "icon", width: "40px" },
    { header: "Host", field: "hostname" },
    { header: "Shards", field: "shards" },
    { header: "Epoch", field: "epoch", width: "growCollapse", minWidth: "40px" },
    { header: "Index version", field: "index_version", width: "growCollapse", minWidth: "20px" },
    { header: "Binary version", field: "binary_version", width: "growCollapse", minWidth: "60px" },
  ];

  let data = missingHosts
    .filter((h) => filterHostnames(filter, h))
    .map((host) => ({
      icon: <Octicon icon={DiffRemovedIcon} sx={{ color: "danger.fg" }} />,
      hostname: <DisplayHostname host={host} />,
    }));
  data.push(
    ...extraHosts
      .filter((h) => filterHostnames(filter, h))
      .map((host) => ({
        icon: <Octicon icon={DiffAddedIcon} sx={{ color: "danger.fg" }} />,
        hostname: <DisplayHostname host={host} />,
      }))
  );
  data.push(
    ...assignments
      .filter((h) => filterHosts(filter, h))
      .sort(sortHosts)
      .map((host) => {
        const extra = (corpus.hosts || []).find((h) => h.hostname === host.hostname);
        return {
          icon: <Octicon icon={ServerIcon} sx={{ color: extra ? "success.fg" : "fg.subtle" }} />,
          hostname: <DisplayHostname host={host.hostname} />,
          shards: <ShardList host={host} extra={extra} />,
          epoch: extra ? `e${extra.epoch_id}` : null,
          index_version: extra ? `v${extra.index_version}` : null,
          binary_version: (
            <Truncate inline expandable title={extra?.binary_version} as="span" sx={{ maxWidth: 60 }}>
              <Text fontFamily="mono">{extra?.binary_version}</Text>
            </Truncate>
          ),
        };
      })
  );

  const inner = (
    <Box sx={{ display: "flex", flexDirection: "column" }}>
      <h3>{snapshot ? `${data.length} hosts` : "Loading hosts…"}</h3>
      <Table.Container>
        <Table.Subtitle>
          <Stack>
            {(extraHosts.length > 0 || missingHosts.length > 0) && (
              <Stack gap="none">
                {extraHosts.length > 0 && (
                  <Text>
                    <Octicon icon={DiffAddedIcon} sx={{ color: "danger.fg", mr: 2 }} />
                    {extraHosts.length} extra host(s) not participating in DSA
                  </Text>
                )}
                {missingHosts.length > 0 && (
                  <Text>
                    <Octicon icon={DiffRemovedIcon} sx={{ color: "danger.fg", mr: 2 }} />
                    Sites API missing {missingHosts.length} host(s)
                  </Text>
                )}
              </Stack>
            )}
            <TextInput
              leadingVisual={SearchIcon}
              value={filter}
              width="100%"
              sx={{ mb: snapshot ? 0 : 2 }} // NB: Skeleton has some spacing issues
              onChange={(e) => setFilter(e.target.value)}
              aria-label="Host filter"
              id="host-filter"
              placeholder="Filter by hostname, state, or shard id"
            />
          </Stack>
        </Table.Subtitle>
        <DataTable cellPadding="condensed" columns={columns} data={data} />
        {!snapshot && <Table.Skeleton columns={columns} rows={5} />}
      </Table.Container>
      <Stack>
        {snapshot?.offset && (
          <Text color="fg.subtle" fontSize={0} sx={{ pt: 4 }}>
            <PrimerLink sx={{ ml: 1 }} as={Link} to={`?offset=${parseInt(snapshot.offset, 10) - 1}`}>
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
            <Text sx={{ mx: 2 }} color="fg.subtle">
              |
            </Text>
            DSA offset: {snapshot.offset} ({snapshot.snapshot_time})
          </Text>
        )}
      </Stack>
    </Box>
  );

  return (
    <>
      {snapshot?.failed ? (
        <Flash variant="danger">Failed to get shard assignments: {snapshot.error.statusText}</Flash>
      ) : (
        <Box>{inner}</Box>
      )}
    </>
  );
}

function ShardList({ host, extra }) {
  return (
    <Stack key={`shardlist-${host.hostname}`} gap="none" direction="horizontal">
      {host.assigned_shards.map((shard) => {
        const shardExtra = (extra?.shards || []).find((s) => s.shard_id === shard.shard_id);
        let variant = variantForState(shard.state);
        if (shard.state === "SERVING" && !shardExtra) {
          variant = "secondary";
        }
        const tooltip = `${shard.state} | Serving Offset: ${
          shardExtra?.serving_offset || "unknown"
        } | Serving Timestamp: ${new Date(parseInt(shardExtra?.serving_ts)).toLocaleString()}`;
        return (
          <Stack key={`sl-item-${host.hostname}-${shard.shard_id}`} direction="horizontal" align="center">
            <Tooltip aria-label={tooltip}>
              <Label variant={variant} sx={{ px: 1, py: 1, mr: 1 }}>
                {shard.state !== "SERVING" && <>{shard.state.slice(0, 1)}: </>}
                {shard.shard_id}
              </Label>
            </Tooltip>
          </Stack>
        );
      })}
    </Stack>
  );
}

function ForceBootstrap({ corpus, corpora, fetcher, epochModes, message, deployEnv }) {
  const didBackfill = fetcher.data && fetcher.data.rpcMethod === "BeginBackfillCorpus";
  const [epochMode, setEpochMode] = useState(epochModes[0]);

  const cacheClusters = corpora
    .filter((c) => c.corpus_name.includes("cache"))
    .toSorted((a, b) => a.corpus_name.localeCompare(b.corpus_name));
  let recommendedCacheClusters = [];
  let otherRegionCacheClusters = [];
  for (const c of cacheClusters) {
    if (c.region === corpus.region) {
      recommendedCacheClusters.push(c);
    } else {
      otherRegionCacheClusters.push(c);
    }
  }

  const [mstCacheCluster, setMstCacheCluster] = useState(cacheClusters[0]?.corpus_name);

  return (
    <Box sx={{ mt: 2 }}>
      <InlineMessage variant="warning">Runs an empty backfill. {message}</InlineMessage>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="BeginBackfillCorpus"></input>
        <input type="hidden" name="bootstrap" value="true"></input>
        <Box display="flex" flexDirection="column" sx={{ my: 2 }}>
          <FormControl required>
            <FormControl.Label>Cache Cluster</FormControl.Label>
            <Select
              name="mst_cache_cluster"
              value={mstCacheCluster}
              onChange={(e) => setMstCacheCluster(e.target.value)}
            >
              <Select.Option key="select" value="" disabled>
                Select a cache cluster...
              </Select.Option>
              {recommendedCacheClusters.map((c) => (
                <Select.Option key={c.corpus_name} value={c.corpus_name}>
                  {c.corpus_name} ({c.epoch_mode})
                </Select.Option>
              ))}
              {otherRegionCacheClusters.length > 0 && (
                <>
                  <Select.Option key="other" value="" disabled>
                    Clusters in other regions...
                  </Select.Option>
                  {otherRegionCacheClusters.map((c) => (
                    <Select.Option key={`other-${c.corpus_name}`} value={c.corpus_name}>
                      {c.corpus_name} ({c.epoch_mode})
                    </Select.Option>
                  ))}
                </>
              )}
            </Select>
            <FormControl.Caption>The cache cluster to use for the bootstrap backfill.</FormControl.Caption>
          </FormControl>
          <FormControl sx={{ mt: 2 }} required>
            <FormControl.Label>Epoch Mode</FormControl.Label>
            <Select name="epoch_mode" value={epochMode} onChange={(e) => setEpochMode(e.target.value)}>
              {epochModes.map((mode) => (
                <Select.Option key={mode} value={mode}>
                  {mode}
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

function Backfill({ corpora, corpus, fetcher, deployEnv, epochModes }) {
  const params = useParams();
  const didBackfill = fetcher.data && fetcher.data.rpcMethod === "BeginBackfillCorpus";

  const filteredEpochModes = epochModes.filter((m) => !m.startsWith("EXTERNAL"));

  const isCompatibleMode = (source, target) => {
    // Ban starting a non-lexical epoch from a lexical epoch, since lexical epochs are huge--
    // they contain too many documents to compute embeddings for them all.
    return !(source === "LEXICAL" && target !== "LEXICAL");
  };

  let allCacheClusters = corpora
    .filter((c) => c.corpus_name.includes("cache"))
    .filter((c) => !c.epoch_mode.startsWith("EXTERNAL"))
    .toSorted((a, b) => b.epoch_id - a.epoch_id);
  const recommendedCluster = allCacheClusters.find((c) => c.corpus_name === corpus.cache_cluster);
  const [epochMode, setEpochMode] = useState(recommendedCluster?.epoch_mode || filteredEpochModes[0]);

  let recommendedCacheClusters = [];
  let incompatibleCacheClusters = [];
  let otherCacheClusters = [];
  let otherRegionCacheClusters = [];
  for (const c of allCacheClusters) {
    if (c.epoch_mode === epochMode) {
      if (c.region === corpus.region) {
        recommendedCacheClusters.push(c);
      } else {
        otherRegionCacheClusters.push(c);
      }
    } else if (isCompatibleMode(c.epoch_mode, epochMode)) {
      if (c.region === corpus.region) {
        otherCacheClusters.push(c);
      } else {
        otherRegionCacheClusters.push(c);
      }
    } else {
      incompatibleCacheClusters.push(c);
    }
  }

  const [mstCacheCluster, setMstCacheCluster] = useState(recommendedCluster?.corpus_name);

  const handleEpochIdChange = (event) => {
    const corpusName = event.target.value;
    const c = allCacheClusters.find((c) => c.corpus_name === corpusName);
    setMstCacheCluster(corpusName);
    if (c) {
      setEpochMode(c.epoch_mode);
    }
  };

  const selectedCluster = allCacheClusters.find((c) => c.corpus_name === mstCacheCluster);
  const selectedEpochMode = selectedCluster?.epoch_mode;

  const handleEpochModeChange = (epochMode) => {
    // Try keeping the source cluster unchanged.
    let c = allCacheClusters.find((c) => c.corpus_name === mstCacheCluster);
    if (!c || !isCompatibleMode(c.epoch_mode, epochMode)) {
      // Nope, it's not compatible - search for one that already has the desired mode.
      c = allCacheClusters.find((c) => c.epoch_mode === epochMode);
      if (!c) {
        // Failing that, any compatible mode.
        c = allCacheClusters.find((c) => isCompatibleMode(c.epoch_mode, epochMode));
      }
      setMstCacheCluster(c?.corpus_name);
    }
    setEpochMode(epochMode);
  };

  const coldStart = !corpus.indexing && corpus.ingest_mode === "Legacy";
  if (coldStart) {
    return <ColdStart corpus={corpus} fetcher={fetcher} />;
  }

  const isRecommendedEpoch = recommendedCacheClusters.some((c) => c.corpus_name === mstCacheCluster);

  return (
    <Box sx={{ mt: 2 }}>
      <Box display="flex" flexDirection="column">
        <fetcher.Form method="post">
          <input type="hidden" name="rpcMethod" value="BeginBackfillCorpus"></input>
          <Box display="flex" flexDirection="column">
            <>
              <FormControl required>
                <FormControl.Label>MST Source Epoch</FormControl.Label>
                <Select name="mst_cache_cluster" value={mstCacheCluster} onChange={handleEpochIdChange}>
                  <Select.Option key="b-select" value="" disabled>
                    Recommended epochs...
                  </Select.Option>
                  {recommendedCacheClusters.map((c) => (
                    <Select.Option key={c.corpus_name} value={c.corpus_name}>
                      {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                    </Select.Option>
                  ))}
                  {otherCacheClusters.length > 0 && (
                    <>
                      <Select.Option key="b-other" value="" disabled>
                        Epochs with other modes...
                      </Select.Option>
                      {otherCacheClusters.map((c) => (
                        <Select.Option key={`other-${c.corpus_name}`} value={c.corpus_name}>
                          {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                        </Select.Option>
                      ))}
                    </>
                  )}
                  {otherRegionCacheClusters.length > 0 && (
                    <>
                      <Select.Option key="b-other-regions" value="" disabled>
                        Epochs in other regions...
                      </Select.Option>
                      {otherRegionCacheClusters.map((c) => (
                        <Select.Option key={`other-${c.corpus_name}`} value={c.corpus_name}>
                          {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                        </Select.Option>
                      ))}
                    </>
                  )}
                  {incompatibleCacheClusters.length > 0 ? (
                    <>
                      <Select.Option key="b-incompatible" value="" disabled>
                        Epochs with incompatible modes...
                      </Select.Option>
                      {incompatibleCacheClusters.map((c) => (
                        <Select.Option key={`incompatible-${c.corpus_name}`} value="" disabled>
                          {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                        </Select.Option>
                      ))}
                    </>
                  ) : null}
                </Select>
                <FormControl.Caption>
                  Use the epoch on this cache cluster to generate the MST that will drive backfill.
                </FormControl.Caption>
                <FormControl.Validation>
                  {!isRecommendedEpoch && "⚠️ This epoch is using a different epoch mode."}
                </FormControl.Validation>
              </FormControl>

              <FormControl required sx={{ mt: 2 }}>
                <FormControl.Label>Epoch Mode</FormControl.Label>
                <Select
                  name="epoch_mode"
                  value={epochMode}
                  onChange={(e) => {
                    handleEpochModeChange(e.target.value);
                  }}
                >
                  <Select.Option key="em-recommended" value="" disabled>
                    Recommended epoch modes...
                  </Select.Option>
                  {filteredEpochModes.map((mode) =>
                    isSupportedMode(mode, params.stamp, selectedEpochMode) ? (
                      <Select.Option key={`em-recommended-${mode}`} value={mode}>
                        {mode}
                      </Select.Option>
                    ) : null
                  )}
                  <Select.Option key="em-other" value="" disabled>
                    Other epoch modes...
                  </Select.Option>
                  {filteredEpochModes.map((mode) =>
                    !isSupportedMode(mode, params.stamp, selectedEpochMode) ? (
                      <Select.Option key={`em-other-${mode}`} value={mode}>
                        {mode}
                        {params.stamp !== "dotcom" && " ⚠️"}
                      </Select.Option>
                    ) : null
                  )}
                </Select>
                <FormControl.Caption>
                  Determines the set of repos to index and whether embeddings are to be indexed or not.
                </FormControl.Caption>
                <FormControl.Validation>
                  {!isSupportedMode(epochMode, params.stamp, selectedEpochMode) &&
                    formattedEpochModeWarning(params.stamp)}
                </FormControl.Validation>
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
                Backfill {corpusDisplayName(corpus)}
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
                <Button type="submit">Unpin {corpusDisplayName(corpus)}</Button>
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
                <FormControl.Caption>
                  The timestamp can be specified as an RFC3339 formatted date or as milliseconds since the Unix epoch.
                  <br />
                  Note: It can take up to 30 minutes to pin the cluster to a prior state.
                </FormControl.Caption>
              </FormControl>
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
                  Pin {corpusDisplayName(corpus)}
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
  if (corpus.epoch_mode && corpus.epoch_mode.includes("HYBRID")) {
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

function isSupportedMode(mode, stamp, corpusMode) {
  if (stamp === "dotcom") {
    if (corpusMode !== "") {
      return mode === corpusMode;
    }
    return !mode.toLowerCase().includes("hybrid");
  }
  return mode.toLowerCase().includes("hybrid");
}

function formattedEpochModeWarning(stamp) {
  if (stamp === "dotcom") {
    return `⚠️ This epoch mode is not recommended or does not match the source epoch. Double-check this is what you want.`;
  }
  return `⚠️ Only 'hybrid' epoch modes that can serve both lexical and semantic queries are supported in Proxima.`;
}

function BranchEpoch({ corpus, corpora, fetcher, deployEnv, epochModes }) {
  const params = useParams();
  const clusters = corpora
    .filter((c) => !c.corpus_name.includes("cache"))
    .filter((c) => !c.epoch_mode.startsWith("EXTERNAL"))
    .toSorted((a, b) => b.epoch_id - a.epoch_id);

  let recommendedClusters = [];
  let otherModeClusters = [];
  let otherRegionClusters = [];
  for (const c of clusters) {
    if (c.epoch_mode === corpus.epoch_mode) {
      if (c.region === corpus.region) {
        recommendedClusters.push(c);
      } else {
        otherRegionClusters.push(c);
      }
    } else {
      if (c.region === corpus.region) {
        otherModeClusters.push(c);
      } else {
        otherRegionClusters.push(c);
      }
    }
  }

  const filteredEpochModes = epochModes.filter((m) => !m.startsWith("EXTERNAL"));

  const [selectedCorpus, setSelectedCorpus] = useState(recommendedClusters[0] || clusters[0]);
  const [epochMode, setEpochMode] = useState(selectedCorpus.epoch_mode || filteredEpochModes[0]);
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

  const isRecommendedEpoch = recommendedClusters.some((c) => c.corpus_name === selectedCorpus.corpus_name);

  return (
    <Box sx={{ mt: 2 }}>
      <Box sx={{ display: "flex", flexDirection: "column" }}>
        <fetcher.Form method="post">
          <input type="hidden" name="rpcMethod" value="BranchEpoch" />
          <input type="hidden" name="source_epoch" value={selectedCorpus.epoch_id} />
          <input type="hidden" name="num_shards" value={selectedCorpus.num_shards} />
          <input type="hidden" name="epoch_mode" value={selectedCorpus.epoch_mode} />
          <Box display="flex" flexDirection="column">
            <Box sx={{ display: "flex", alignItems: "center" }}>
              <FormControl required>
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
                  {otherModeClusters.length > 0 && (
                    <>
                      <Select.Option key="be-other" value="" disabled>
                        Epochs with other modes...
                      </Select.Option>
                      {otherModeClusters.map((c) => (
                        <Select.Option key={`be-other-${c.corpus_name}`} value={c.corpus_name}>
                          {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                        </Select.Option>
                      ))}
                    </>
                  )}
                  {otherRegionClusters.length > 0 && (
                    <>
                      <Select.Option key="be-other-regions" value="" disabled>
                        Epochs in other regions...
                      </Select.Option>
                      {otherRegionClusters.map((c) => (
                        <Select.Option key={`be-other-region-${c.corpus_name}`} value={c.corpus_name}>
                          {c.epoch_id}: {c.corpus_name} ({c.epoch_mode})
                        </Select.Option>
                      ))}
                    </>
                  )}
                </Select>
                <FormControl.Caption>Branch from this epoch.</FormControl.Caption>
                <FormControl.Validation>
                  {!isRecommendedEpoch && "⚠️ This epoch is using a different epoch mode."}
                </FormControl.Validation>
              </FormControl>
              <Text sx={{ ml: 2, mt: 2 }} color="fg.subtle" fontSize={1}>
                <b>serving_ts:</b> {selectedCorpus.serving_ts}
                <Tooltip aria-label="Copy to clipboard">
                  <IconButton
                    icon={CopyIcon}
                    size="small"
                    variant="invisible"
                    onClick={() => copyToClipboard(selectedCorpus.serving_ts)}
                  />
                </Tooltip>
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
                <Select.Option key="em-recommended" value="" disabled>
                  Recommended epoch modes...
                </Select.Option>
                {filteredEpochModes
                  .filter(
                    (mode) =>
                      isSupportedMode(mode, params.stamp, selectedCorpus.epoch_mode) && canBranch(selectedCorpus, mode)
                  )
                  .map((mode) => (
                    <Select.Option key={`em-recommended-${mode}`} value={mode}>
                      {mode}
                    </Select.Option>
                  ))}
                <Select.Option key="em-other" value="" disabled>
                  Other epoch modes...
                </Select.Option>
                {filteredEpochModes
                  .filter((mode) => !isSupportedMode(mode, params.stamp, selectedCorpus.epoch_mode))
                  .map((mode) => (
                    <Select.Option key={`em-other-${mode}`} value={mode}>
                      {mode}
                      {params.stamp !== "dotcom" && " ⚠️"}
                    </Select.Option>
                  ))}
              </Select>
              <FormControl.Caption>
                Determines the set of repos to index and whether embeddings are to be indexed or not.
              </FormControl.Caption>
              <FormControl.Validation>
                {!isSupportedMode(epochMode, params.stamp, selectedCorpus.epoch_mode) &&
                  formattedEpochModeWarning(params.stamp)}
              </FormControl.Validation>
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
                Branch from {corpusDisplayName(selectedCorpus)}
              </Button>
            </Box>
          </Box>
        </fetcher.Form>
      </Box>
    </Box>
  );
}

// Checks if any shards are not being served on any hosts in a corpus.
// Used to warn that cache clusters are too unhealthy to switch to.
function hasUnservedShards(corpus) {
  const shardsServed = new Set();
  for (const host of Object.values(corpus.hosts)) {
    for (const shard of host.shards) {
      if (shard.serving_ts !== 0) {
        shardsServed.add(shard.shard_id);
      }
    }
  }
  return shardsServed.size < corpus.num_shards;
}

function SetCacheCluster({ corpus, corpora, fetcher }) {
  const [corpusCacheCluster, setCorpusCacheCluster] = useState(corpus.cache_cluster);

  let allCacheClusters = corpora.filter((c) => c.corpus_name.includes("cache"));
  let recommendedCacheClusters = [];
  let otherModeCacheClusters = [];
  let otherRegionCacheClusters = [];
  for (const c of allCacheClusters) {
    if (c.epoch_mode === corpus.epoch_mode || c.epoch_mode.includes("HYBRID")) {
      if (c.region === corpus.region) {
        recommendedCacheClusters.push(c);
      } else {
        otherRegionCacheClusters.push(c);
      }
    } else {
      if (c.region === corpus.region) {
        otherModeCacheClusters.push(c);
      } else {
        otherRegionCacheClusters.push(c);
      }
    }
  }

  let selectedCorpus = corpora.find((c) => c.corpus_name === corpusCacheCluster);
  return (
    <Box>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="SetCorpusCacheCluster"></input>
        <Stack direction="horizontal" gap="condensed" justify="space-between">
          <FormControl required>
            <FormControl.Label>Cache Cluster</FormControl.Label>
            <Select
              name="cache_cluster"
              value={corpusCacheCluster}
              size="small"
              onChange={(e) => setCorpusCacheCluster(e.target.value)}
            >
              <Select.Option key="select" value="" disabled>
                Select a cache cluster...
              </Select.Option>
              {recommendedCacheClusters.map((c) => (
                <Select.Option key={c.corpus_name} value={c.corpus_name}>
                  {c.corpus_name} ({c.epoch_mode}){hasUnservedShards(c) && " ⚠️"}
                </Select.Option>
              ))}
              {otherModeCacheClusters.length > 0 && (
                <>
                  <Select.Option key="other-mode" value="" disabled>
                    Clusters with incompatible modes...
                  </Select.Option>
                  {otherModeCacheClusters.map((c) => (
                    <Select.Option key={`other-${c.corpus_name}`} value={c.corpus_name}>
                      {c.corpus_name} ({c.epoch_mode}){hasUnservedShards(c) && " ⚠️"}
                    </Select.Option>
                  ))}
                </>
              )}
              {otherRegionCacheClusters.length > 0 && (
                <>
                  <Select.Option key="other-region" value="" disabled>
                    Clusters in other regions...
                  </Select.Option>
                  {otherRegionCacheClusters.map((c) => (
                    <Select.Option key={`other-${c.corpus_name}`} value={c.corpus_name}>
                      {c.corpus_name} ({c.epoch_mode}){hasUnservedShards(c) && " ⚠️"}
                    </Select.Option>
                  ))}
                </>
              )}
            </Select>
            <FormControl.Caption>
              {selectedCorpus && selectedCorpus.epoch_mode.includes("EXTERNAL")
                ? "Publishes documents, extracts symbols, and fetches embeddings for ingest."
                : "Reduces the load on spokes, extracts symbols, and fetches embeddings during ingest."}
            </FormControl.Caption>
            <FormControl.Validation>
              {selectedCorpus &&
                hasUnservedShards(selectedCorpus) &&
                "⚠️ Not all shards are served by this cache cluster."}
              {selectedCorpus &&
                selectedCorpus.region !== corpus.region &&
                "⚠️ This cache cluster is in a different region and can't publish to the right kafka topics."}
            </FormControl.Validation>
          </FormControl>
          <Box>
            <Text sx={{ height: "21px" }}>&nbsp;</Text>
            <Button type="submit" size="small">
              Save
            </Button>
          </Box>
        </Stack>
      </fetcher.Form>
    </Box>
  );
}

function ColorBar({ corpus, isCacheCluster }) {
  return (
    <Box sx={{ display: "flex", border: "0px solid", borderRadius: 1, borderColor: "border.muted", minHeight: 79 }}>
      {corpus.snapshot ? (
        corpus.snapshot.failed ? (
          <Flash variant="danger" sx={{ display: "flex", flex: 1 }}>
            Failed to get shard assignments: <br />
            {corpus.snapshot.error.statusText}
          </Flash>
        ) : (
          <PrettyBoxes corpus={corpus} isCacheCluster={isCacheCluster} />
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

function PrettyBoxes({ corpus, isCacheCluster }) {
  const { snapshot } = corpus;
  const m = new Map();
  const shardSet = new Set();
  (snapshot?.host_assignments || []).forEach((host) => {
    const extra = (corpus.hosts || []).find((h) => h.hostname === host.hostname);
    (host.assigned_shards || []).forEach((shard, i) => {
      const shardExtra = (extra?.shards || []).find((s) => s.shard_id === shard.shard_id);
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
        shardExtra: shardExtra,
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
              let color = dsaStates[host.state.toLowerCase()];
              if (!color) {
                color = "neutral.muted";
              } else if (host.isServing && !host.shardExtra) {
                color = "neutral.muted";
              } else {
                const emphasis = host.isPrimary || !host.isServing;
                color = `${color}.${emphasis ? "emphasis" : "muted"}`;
              }
              return (
                <Tooltip
                  key={`cb-${host.hostname}-${i}`}
                  aria-label={`${host.hostname}\n${host.state}: ${shard_id}${primary}`}
                >
                  <Box
                    minHeight={15}
                    border="1px solid"
                    borderRadius={1}
                    borderColor="border.muted"
                    sx={{ bg: color }}
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
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="IndexRepoList" />
        <input type="hidden" name="repo_ids" value={JSON.stringify(repoList)} />
        <Box display="flex">
          <FormControl required sx={{ mt: 2 }}>
            <FormControl.Label visuallyHidden>Repo ids</FormControl.Label>
            <Textarea name="repoListDisplay" onChange={handleTextareaChange} value={textAreaValue} />
            <FormControl.Caption>Enter a newline separated list of repo ids</FormControl.Caption>
          </FormControl>
        </Box>
        <Box display="flex" alignItems="center" sx={{ mt: 2 }}>
          <Button
            variant="danger"
            type="submit"
            width="100"
            onClick={(e) => {
              if (repoList.length === 0) {
                window.alert("Please enter at least one repo");
                e.preventDefault();
              }
            }}
          >
            Index repos
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
  unknown: "neutral",
};

function variantForState(state) {
  let variant = dsaStates[(state || "").toLowerCase()];
  if (!variant) {
    variant = "danger";
  }
  return variant;
}

function filterHostnames(filter, h) {
  return filter === "" || h.includes(filter);
}

function filterHosts(filter, h) {
  return (
    filter === "" ||
    h.hostname.includes(filter) ||
    h.assigned_shards.filter((s) => s.state.toLowerCase().startsWith(filter) || s.shard_id.toString() === filter)
      .length > 0
  );
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

function DisplayHostname({ host }) {
  return (
    <Stack direction="horizontal" gap="condensed" justify="space-between" align="center">
      <Text fontFamily="mono">{host}</Text>
      <Tooltip aria-label="Copy to clipboard, hold <Shift> to copy only the hostname" direction="n">
        <IconButton
          icon={CopyIcon}
          size="small"
          variant="invisible"
          onClick={(e) => copyHostnameToClipboard(host, e)}
        />
      </Tooltip>
    </Stack>
  );
}

function copyHostnameToClipboard(text, e) {
  if (e?.shiftKey) {
    // If shift is held, copy only the first segment before a '.'
    text = text.split(".")[0];
  }
  navigator.clipboard.writeText(text);
}

function copyToClipboard(text) {
  navigator.clipboard.writeText(text);
}
